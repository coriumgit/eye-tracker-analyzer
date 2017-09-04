classdef EyeTrackerAnalysisRecord < handle
    properties (Access= public, Constant)
        CONDS_NAMES_PREFIX= 'c';
    end
    
    properties (Access= private, Constant)
        SAND_BOX_RELATIVE_PATH= fullfile('EDF_convertion', 'sandbox');        
    end
    
    properties (Access= private)          
        analysis_tag;
        eye_tracker_data_structs;
        is_eeg_involved;
        segmentization_vecs_index= {};
        segmentization_vecs= {};
        saccades_extractors_data= {};
        chosen_segmentization_i= 0;
        progress_screen;  
        dpp = [];
        sampling_rate = [];
    end
    
    methods (Access= public)
        function obj= EyeTrackerAnalysisRecord(progress_screen, progress_contribution, analysis_tag, eye_tracker_files, dpp)             
            obj.analysis_tag= analysis_tag; 
            obj.dpp = dpp;          
            curr_path= pwd;            
            if ~iscell(eye_tracker_files)
                eye_tracker_files= {eye_tracker_files};
            end
            eye_tracker_files_nr= numel(eye_tracker_files);
            obj.is_eeg_involved= false;
            obj.eye_tracker_data_structs= {};            
            for eye_tracker_file_i= 1:eye_tracker_files_nr                 
                curr_eye_tracker_full_file_name= eye_tracker_files{eye_tracker_file_i};
                [~, eye_tracker_file_name, eye_tracker_file_ext]= fileparts(curr_eye_tracker_full_file_name);                                    
                if strcmp(eye_tracker_file_ext, '.edf')                    
                    copyfile(curr_eye_tracker_full_file_name, EyeTrackerAnalysisRecord.SAND_BOX_RELATIVE_PATH);
                    progress_screen.displayMessage(['converting session #', num2str(eye_tracker_file_i), ' edf file']);
                    cd(EyeTrackerAnalysisRecord.SAND_BOX_RELATIVE_PATH);
                    extracted_structs = {readEDF([eye_tracker_file_name, '.edf'])};                                      
                    delete([eye_tracker_file_name, '.edf']);
                    cd(curr_path);                  
                elseif strcmp(eye_tracker_file_ext, '.mat')
                    progress_screen.displayMessage(['loading session #', num2str(eye_tracker_file_i), ' mat file']);
                    loaded_mat= load(curr_eye_tracker_full_file_name);
                    extracted_structs = EyeTrackerAnalysisRecord.extractEyeTrackerStructsFromLoadedMatStructs(loaded_mat);                    
                    if isempty(extracted_structs)                        
                        error('EyeTrackerAnalysisRecord:InvalidMat', [eye_tracker_file_name, '.mat does not contain an eyelink data struct.']);                                    
                    end                    
                elseif strcmp(eye_tracker_file_ext, '.set')                    
                    extracted_structs = {EyeTrackerAnalysisRecord.addEtaFieldsToEegStruct(pop_loadset(curr_eye_tracker_full_file_name))};                    
                    obj.is_eeg_involved= true;
                end
                
                if numel(extracted_structs) == 1
                    extracted_structs = {extracted_structs};
                end
                
                if eye_tracker_file_i == 1
                    obj.sampling_rate = 1000 / (extracted_structs{1}.gazeRight.time(2) - extracted_structs{1}.gazeRight.time(1));
                else   
                    for session_i = 1:numel(extracted_structs)
                        curr_session_sampling_rate = 1000 / (extracted_structs{session_i}.gazeRight.time(2) - extracted_structs{session_i}.gazeRight.time(1));
                        if curr_session_sampling_rate ~= obj.sampling_rate
                            error('EyeTrackerAnalysisRecord:InvalidMat', [eye_tracker_file_name, 'contains data with different sampling rate (', num2str(curr_session_sampling_rate), ' Hz) than does the first session file (', num2str(obj.sampling_rate), ' Hz) - sessions with different sampling rates are not supported.']);                    
                        end
                    end
                end
                
                obj.eye_tracker_data_structs= [obj.eye_tracker_data_structs, extracted_structs];  
                progress_screen.addProgress(progress_contribution/eye_tracker_files_nr);
            end                         
        end                
                  
        function was_previous_segmentization_loaded= segmentizeData(obj, progress_screen, progress_contribution, trial_onset_triggers, trial_offset_triggers, trial_rejection_triggers, baseline, post_offset_triggers_segment, trial_dur, blinks_delta)
            segmentizations_nr= numel(obj.segmentization_vecs);            
            for segmentization_i= 1:segmentizations_nr
                if isempty( setxor(obj.segmentization_vecs_index{segmentization_i, 1}, trial_onset_triggers) ) && ...
                        obj.segmentization_vecs_index{segmentization_i, 2} == trial_dur && ...
                        obj.segmentization_vecs_index{segmentization_i, 3} == baseline && ...
                        obj.segmentization_vecs_index{segmentization_i, 4} == blinks_delta && ...
                        isempty( setxor(obj.segmentization_vecs_index{segmentization_i, 5}, trial_offset_triggers) ) && ...
                        ( isempty(obj.segmentization_vecs_index{segmentization_i, 6}) && isempty(post_offset_triggers_segment) || ...
                          ~isempty(obj.segmentization_vecs_index{segmentization_i, 6}) && ~isempty(post_offset_triggers_segment) && obj.segmentization_vecs_index{segmentization_i, 6} == post_offset_triggers_segment ) && ...
                        isempty( setxor(obj.segmentization_vecs_index{segmentization_i, 7}, trial_rejection_triggers) )  
                      
                    obj.chosen_segmentization_i= segmentization_i;                    
                    was_previous_segmentization_loaded= true;
                    progress_screen.addProgress(progress_contribution);
                    return;
                end
            end
            
            was_previous_segmentization_loaded = false;
            sessions_nr = numel(obj.eye_tracker_data_structs);            
            for session_i= 1:sessions_nr
                curr_session_eye_tracker_data_struct= obj.eye_tracker_data_structs{session_i};                                                               
                %progress_screen.displayMessage(['session #', num2str(session_i), ': indexing blinks']);
                obj.segmentization_vecs{segmentizations_nr+1}(session_i).blinks= EyeTrackerAnalysisRecord.blinks_vec_gen(curr_session_eye_tracker_data_struct, blinks_delta, progress_screen, 0.8*progress_contribution/sessions_nr);                                                                
                triggers_nr= numel(trial_onset_triggers);                
                for trigger_i= 1:triggers_nr                    
                    %progress_screen.displayMessage(['session #', num2str(session_i), ': segmentizing data by condition ', trial_onset_triggers{trigger_i}]);
                    if all(isstrprop(trial_onset_triggers{trigger_i},'digit'))                                                
                        curr_cond_field_name = [obj.CONDS_NAMES_PREFIX, trial_onset_triggers{trigger_i}];
                        [start_times, end_times] = extractSegmentsTimesFromInputs(curr_session_eye_tracker_data_struct, str2double(trial_onset_triggers{trigger_i}));
                        if numel(start_times)==0
                            [start_times, end_times] = extractSegmentsTimesFromMessages(curr_session_eye_tracker_data_struct, trial_onset_triggers{trigger_i});
                        end
                    else                                                
                        curr_cond_field_name = convertMsgToValidFieldName(trial_onset_triggers{trigger_i});                                                
                        [start_times, end_times] = extractSegmentsTimesFromMessages(curr_session_eye_tracker_data_struct, trial_onset_triggers{trigger_i});                                                
                    end

                    if numel(start_times)==0
                        obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_start_times.(curr_cond_field_name)= [];
                        obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_end_times.(curr_cond_field_name)= [];
                        progress_screen.displayMessage(['session #', num2str(session_i), ':Didn''t find trigger ', '''', trial_onset_triggers{trigger_i}, '''']);
                        progress_screen.addProgress(0.2*progress_contribution/(sessions_nr*triggers_nr));
                        continue;
                    end                                                           
                    
                    %assign trials timings 
                    trials_nr= numel(start_times);
                    obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_start_times.(curr_cond_field_name)= NaN(trials_nr, 1);
                    obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_end_times.(curr_cond_field_name)= NaN(trials_nr, 1);
                    session_samples_nr = numel(curr_session_eye_tracker_data_struct.gazeLeft.time);
                    for trial_i=1:trials_nr                          
                        indStart= find(ismember(curr_session_eye_tracker_data_struct.gazeLeft.time, start_times(trial_i) + (0 : (1000/obj.sampling_rate - 1))), 1);
                        if isempty(indStart)
                            continue;
                        end
                        
                        obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_start_times.(curr_cond_field_name)(trial_i) = indStart;
                        if ~isempty(trial_offset_triggers)                            
                            obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_end_times.(curr_cond_field_name)(trial_i) = ...
                                find(ismember(curr_session_eye_tracker_data_struct.gazeLeft.time, end_times(trial_i) + (0 : (1000/obj.sampling_rate - 1))), 1);
                        else
                            obj.segmentization_vecs{segmentizations_nr+1}(session_i).trials_end_times.(curr_cond_field_name)(trial_i) = ...
                                indStart + min(ceil(trial_dur/(1000/obj.sampling_rate)) - 1, session_samples_nr - indStart);
                        end
                    end 
                    
                    progress_screen.addProgress(0.2*progress_contribution/(sessions_nr*triggers_nr));
                end 
            end                        
        
            obj.segmentization_vecs_index{segmentizations_nr+1, 1}= trial_onset_triggers;
            obj.segmentization_vecs_index{segmentizations_nr+1, 2}= trial_dur;
            obj.segmentization_vecs_index{segmentizations_nr+1, 3}= baseline;
            obj.segmentization_vecs_index{segmentizations_nr+1, 4}= blinks_delta;
            obj.segmentization_vecs_index{segmentizations_nr+1, 5}= trial_offset_triggers;
            obj.segmentization_vecs_index{segmentizations_nr+1, 6}= post_offset_triggers_segment;
            obj.segmentization_vecs_index{segmentizations_nr+1, 7}= trial_rejection_triggers;
            
            obj.saccades_extractors_data{segmentizations_nr+1}= [];
            obj.chosen_segmentization_i= numel(obj.segmentization_vecs);
            
            function msg = convertMsgToValidFieldName(msg)
                msg(ismember(msg,' -')) = '_';                
                if isstrprop(msg(1),'digit')
                    msg = [obj.CONDS_NAMES_PREFIX, msg];
                end                
            end
            
            function [start_times, end_times] = extractSegmentsTimesFromMessages(eye, trial_onset_trigger)
                % search phases:
                % 1 - trial onset
                % 2 - trial offset
                are_offset_triggers_included = ~isempty(trial_offset_triggers);
                start_times= []; 
                end_times = [];
                field_i = 1;                
                search_phase = 1;
                while field_i <= numel(eye.messages)                    
                    msg = eye.messages(field_i).message;
                    if isempty(msg)
                        field_i = field_i + 1;
                        continue;
                    end
                    
                    msg_time = eye.messages(field_i).time;
                    if search_phase == 1
                        if strcmp(msg, trial_onset_trigger)                            
                            potential_trial_start_time = msg_time;
                            search_phase = 2;
                        end
                    elseif (are_offset_triggers_included && any(cellfun(@(str) strcmp(str, msg), trial_offset_triggers))) || ...
                           (~are_offset_triggers_included && (strcmp(msg, trial_onset_trigger) || msg_time - potential_trial_start_time > trial_dur - baseline))
                        search_phase = 1;
                        start_times= [start_times, potential_trial_start_time - baseline]; %#ok<AGROW>
                        if are_offset_triggers_included
                            end_times = [end_times, msg_time + post_offset_triggers_segment]; %#ok<AGROW>                                                                        
                        else
                             continue;
                        end
                    elseif any(cellfun(@(str) strcmp(str, msg), trial_rejection_triggers))
                        search_phase = 1;
                    end
                    
                    field_i = field_i + 1;
                end                                                                                                                
            end                                      
            
            function [start_times, end_times] = extractSegmentsTimesFromInputs(eye, trial_onset_trigger, baseline, post_offset_triggers_segment, trial_dur)
                % search phases:
                % 1 - trial onset
                % 2 - trial offset
                are_offset_triggers_included = ~isempty(trial_offset_triggers);
                start_times= []; 
                end_times = [];
                field_i = 1;                
                search_phase = 1;
                while field_i <= numel(eye.inputs)                    
                    input = eye.inputs(field_i).input;
                    if isempty(input)
                        field_i = field_i + 1;
                        continue;
                    end
                    
                    input_time = eye.inputs(field_i).time;
                    if search_phase == 1
                        if strcmp(input, trial_onset_trigger)                            
                            potential_trial_start_time = input_time;
                            search_phase = 2;
                        end
                    elseif (are_offset_triggers_included && any(cellfun(@(input) input == eye.inputs(field_i).input, trial_offset_triggers))) || ...
                           (~are_offset_triggers_included && (strcmp(input, trial_onset_trigger) || input_time - potential_trial_start_time > trial_dur - baseline))
                        search_phase = 1;
                        start_times= [start_times, potential_trial_start_time - baseline]; %#ok<AGROW>
                        if are_offset_triggers_included
                            end_times = [end_times, input_time + post_offset_triggers_segment]; %#ok<AGROW>                                                                        
                        else
                             continue;
                        end
                    elseif any(cellfun(@(input) input == eye.inputs(field_i).input, trial_rejection_triggers))
                        search_phase = 1;
                    end
                    
                    field_i = field_i + 1;
                end                                                                             
            end                                
        end
        
        function segmentized_data= getSegmentizedData(obj, filter_bandpass)
            if obj.chosen_segmentization_i==0
                error('EyeTrackerAnalysisRecord:noSegmentizationChosen', 'must call segmentizeData() prior to getSegmentizedData() so segmentized data would be chosen/created');                
            end
                        
            sessions_nr= numel(obj.segmentization_vecs{obj.chosen_segmentization_i});
            segmentized_data_unmerged= cell(1,sessions_nr);
            for session_i= 1:sessions_nr                
                curr_session_segmentization_vecs_struct= obj.segmentization_vecs{obj.chosen_segmentization_i}(session_i);
                curr_session_eye_tracker_data_struct= EyeTrackerAnalysisRecord.filterEyeData(obj.eye_tracker_data_structs{session_i}, filter_bandpass, obj.sampling_rate);
                conds_names= fieldnames(curr_session_segmentization_vecs_struct.trials_start_times);                
                for cond_name_i= 1:numel(conds_names)
                    curr_cond_name= conds_names{cond_name_i}; 
                    trials_nr= numel(curr_session_segmentization_vecs_struct.trials_start_times.(curr_cond_name));
                    if trials_nr==0
                        segmentized_data_unmerged{session_i}.(curr_cond_name)= [];
                    else
                        for trial_i= 1:trials_nr
                            indStart= curr_session_segmentization_vecs_struct.trials_start_times.(curr_cond_name)(trial_i);
                            if isnan(indStart)
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).onset_from_session_start= [];
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).samples_nr= [];
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).blinks= [];                                
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft= [];
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight= [];                                
                                continue;
                            end
                            segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).onset_from_session_start= indStart;
                            indEnd= curr_session_segmentization_vecs_struct.trials_end_times.(curr_cond_name)(trial_i);
                            segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).samples_nr= indEnd - indStart + 1;
                            segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).blinks= curr_session_segmentization_vecs_struct.blinks(indStart:indEnd);                             
                            
                            %if only one eye was recorded save everything to both gazeRight and gazeLeft
                            if obj.eye_tracker_data_structs{session_i}.gazeRight.x(1)<-30000 || obj.eye_tracker_data_structs{session_i}.gazeLeft.x(1)<-30000
                                if curr_session_eye_tracker_data_struct.gazeLeft.x(1)>-30000
                                    gaze= curr_session_eye_tracker_data_struct.gazeLeft;
                                else
                                    gaze= curr_session_eye_tracker_data_struct.gazeRight;
                                end
                                                                
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.x= gaze.x(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.y= gaze.y(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.pupil= gaze.gazeRight.pupil(indStart:indEnd);                                 
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.x= segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.x;
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.y= segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.y;
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.pupil= segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.pupil;
                            else                                                            
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.x= curr_session_eye_tracker_data_struct.gazeLeft.x(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.y= curr_session_eye_tracker_data_struct.gazeLeft.y(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeLeft.pupil= curr_session_eye_tracker_data_struct.gazeLeft.pupil(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.x= curr_session_eye_tracker_data_struct.gazeRight.x(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.y= curr_session_eye_tracker_data_struct.gazeRight.y(indStart:indEnd);
                                segmentized_data_unmerged{session_i}.(curr_cond_name)(trial_i).gazeRight.pupil= curr_session_eye_tracker_data_struct.gazeRight.pupil(indStart:indEnd);
                            end
                        end
                    end
                end
            end
            
            %merge sessions' structs                        
            if sessions_nr>1                
                conds_names= fieldnames(obj.segmentization_vecs{obj.chosen_segmentization_i}(1).trials_start_times);            
                for cond_i= 1:numel(conds_names)     
                    curr_merged_cond_name= conds_names{cond_i};
                    segmentized_data.(curr_merged_cond_name)= [];
                    for merged_session_i= 1:sessions_nr                                                                                                           
                        if ~isempty(segmentized_data_unmerged{merged_session_i}.(curr_merged_cond_name))
                            segmentized_data.(curr_merged_cond_name)= ...
                                [segmentized_data.(curr_merged_cond_name), segmentized_data_unmerged{merged_session_i}.(curr_merged_cond_name)];                        
                        end
                    end
                end                                                  
            else
                segmentized_data= segmentized_data_unmerged{1};                
            end                              
        end
                
        function registerSaccadesAnalysis(obj, saccades_analysis_struct)
            if obj.chosen_segmentization_i==0
                error('EyeTrackerAnalysisRecord:noSegmentizationChosen', 'data of an EyeTrackerAnalysisRecord object has to be segmentized prior to analysis');                
            end
                       
            obj.saccades_extractors_data{obj.chosen_segmentization_i}= saccades_analysis_struct;
        end
        
        function saccades_analysis_struct= loadSaccadesAnalysis(obj)
            if obj.chosen_segmentization_i==0
                error('EyeTrackerAnalysisRecord:noSegmentizationChosen', 'data of an EyeTrackerAnalysisRecord object has to be segmentized prior to analysis');                
            end                        
            
            saccades_analysis_struct= obj.saccades_extractors_data{obj.chosen_segmentization_i};
        end
        
        function analysis_tag= getAnalysisTag(obj)
            analysis_tag= obj.analysis_tag;
        end  
        
        function eye_tracker_data_structs= getEyeTrackerDataStructs(obj)
            eye_tracker_data_structs= obj.eye_tracker_data_structs;
        end
        
        function dpp = getDpp(obj)
            dpp = obj.dpp;
        end
        
        function sampling_rate = getSamplingRate(obj)
            sampling_rate = obj.sampling_rate;
        end
        
        function save(obj, save_folder)
            eta= obj; %#ok<NASGU>
            % segmentization_vecs_index= {};
            % segmentization_vecs= {};
            save(fullfile(save_folder, [obj.analysis_tag, '.eta']), 'eta');
        end
        
        function is_eeg_involved= isEegInvolved(obj)
            is_eeg_involved= obj.is_eeg_involved;
        end
    end
    
    methods (Access= private, Static)                    
        function eye_tracking_data_structs= extractEyeTrackerStructsFromLoadedMatStructs(loaded_struct)
            eye_tracking_data_structs= {};
            fields_names= fieldnames(loaded_struct);
            for field_i= 1:numel(fields_names)
                curr_tested_variable= loaded_struct.(fields_names{field_i});
                if isstruct(curr_tested_variable)
                    if isStructAnEyeDataStruct(curr_tested_variable)
                        eye_tracking_data_structs= [eye_tracking_data_structs, curr_tested_variable]; %#ok<AGROW>
                    end
                elseif iscell(curr_tested_variable)                 
                    for slot_i= 1:numel(curr_tested_variable)
                        if isStructAnEyeDataStruct(curr_tested_variable{slot_i})
                            eye_tracking_data_structs= [eye_tracking_data_structs, curr_tested_variable{slot_i}]; %#ok<AGROW>                         
                        end
                    end                   
                end
            end
                                     
            function res= isStructAnEyeDataStruct(struct)
                if numel(fieldnames(struct))~= 14 || ...
                        ~isfield(struct, 'filename') || ...
                        ~isfield(struct, 'numElements') || ...
                        ~isfield(struct, 'numTrials') || ...
                        ~isfield(struct, 'EDFAPI') || ...
                        ~isfield(struct, 'preamble') || ...
                        ~isfield(struct, 'gazeLeft') || ...
                        ~isfield(struct, 'gazeRight') || ...
                        ~isfield(struct, 'fixations') || ...
                        ~isfield(struct, 'saccades') || ...
                        ~isfield(struct, 'blinks') || ...
                        ~isfield(struct, 'messages') || ...
                        ~isfield(struct, 'gazeCoords') || ...
                        ~isfield(struct, 'frameRate') || ...
                        ~isfield(struct, 'inputs')
                    res= false;
                    return;
                end
                
                if ~isValidGazeStruct(struct.gazeLeft)  || ~isValidGazeStruct(struct.gazeRight)
                    res= false;
                    return;
                end
                
                fixations_struct= struct.fixations;
                if numel(fieldnames(fixations_struct))~= 4 || ...
                        ~isfield(fixations_struct, 'startTime') || ...
                        ~isfield(fixations_struct, 'endTime') || ...
                        ~isfield(fixations_struct, 'aveH') || ...
                        ~isfield(fixations_struct, 'aveV')
                    res= false;
                    return;
                end
                
                saccades_struct= struct.saccades;
                if numel(fieldnames(saccades_struct))~= 7 || ...
                        ~isfield(saccades_struct, 'startTime') || ...
                        ~isfield(saccades_struct, 'endTime') || ...
                        ~isfield(saccades_struct, 'startH') || ...
                        ~isfield(saccades_struct, 'startV') || ...
                        ~isfield(saccades_struct, 'endH') || ...
                        ~isfield(saccades_struct, 'endV') || ...
                        ~isfield(saccades_struct, 'peakVel')
                    res= false;
                    return;
                end
                
                blinks_struct= struct.blinks;
                if numel(fieldnames(blinks_struct))~= 2 || ...
                        ~isfield(blinks_struct, 'startTime') || ...
                        ~isfield(blinks_struct, 'endTime')
                    res= false;
                    return;
                end
                
                if isempty(struct.messages)  || ...
                        numel(fieldnames(struct.messages(1)))~=2 || ...
                        ~isfield(struct.messages(1), 'message') || ...
                        ~isfield(struct.messages(1), 'time')
                    res= false;
                    return;
                end
                
                if isempty(struct.inputs)  || ...
                        numel(fieldnames(struct.inputs(1)))~=2 || ...
                        ~isfield(struct.inputs(1), 'input') || ...
                        ~isfield(struct.inputs(1), 'time')
                    res= false;
                    return;
                end
                
                res= true;
                % === TYPES CHECK NOT INCLUDED ===
                %         if ~ischar(struct.filename) || ...
                %            ~isnumeric(struct.numElements) || ...
                %            numel(struct.numElements)~=1 || ...
                %            ~isnumeric(struct.numTrials) || ...
                %            numel(struct.numTrials)~=1 || ...
                %            ~ischar(struct.EDFAPI) || ...
                %            ~ischar(struct.preamble) || ...
                %            ~isnumeric(struct.gazeCoords) || ...
                %            numel(struct.gazeCoords)~=4 || ...
                %            ~isnumeric(struct.frameRate) || ...
                %            numel(struct.frameRate)~=1
                %             res= false;
                %             return;
                %         end
                function res= isValidGazeStruct(struct)
                    if numel(fieldnames(struct))~= 9 || ...
                            ~isfield(struct, 'time') || ...
                            ~isfield(struct, 'x') || ...
                            ~isfield(struct, 'y') || ...
                            ~isfield(struct, 'pupil') || ...
                            ~isfield(struct, 'pix2degX') || ...
                            ~isfield(struct, 'pix2degY') || ...
                            ~isfield(struct, 'velocityX') || ...
                            ~isfield(struct, 'velocityY') || ...
                            ~isfield(struct, 'whichEye')
                        res= false;
                    else
                        res= true;
                    end
                end
            end
        end
        
        function updated_eeg_struct= addEtaFieldsToEegStruct(eeg_struct)          
            updated_eeg_struct= eeg_struct;
            updated_eeg_struct.gazeLeft.x= double(eeg_struct.data(74,:));
            updated_eeg_struct.gazeLeft.y= double(eeg_struct.data(75,:));
            updated_eeg_struct.gazeLeft.time= 1:numel(updated_eeg_struct.gazeLeft.x);
            updated_eeg_struct.gazeRight.x= double(eeg_struct.data(77,:));
            updated_eeg_struct.gazeRight.y= double(eeg_struct.data(78,:));
            updated_eeg_struct.gazeRight.time= 1:numel(updated_eeg_struct.gazeRight.x);

            for trigger_i= 1:numel(eeg_struct.event)                                
                updated_eeg_struct.messages(trigger_i).time= eeg_struct.event(trigger_i).latency;
                updated_eeg_struct.messages(trigger_i).message= eeg_struct.event(trigger_i).type;
                updated_eeg_struct.inputs(trigger_i).time= [];
                updated_eeg_struct.inputs(trigger_i).input= [];
            end
            
            updated_eeg_struct.blinks.startTime= [];
            updated_eeg_struct.blinks.endTime= [];
            for event_i= 1:numel(eeg_struct.event)
                if strcmp(eeg_struct.event(event_i).type,'R_blink') || strcmp(eeg_struct.event(event_i).type,'L_blink')
                    updated_eeg_struct.blinks.startTime= [updated_eeg_struct.blinks.startTime, eeg_struct.event(event_i).latency];
                    updated_eeg_struct.blinks.endTime= [updated_eeg_struct.blinks.endTime, eeg_struct.event(event_i).latency + eeg_struct.event(event_i).duration];
                end
            end            
        end
            
        function eye_data_struct= filterEyeData(eye_data_struct, bandpass, rate)            
            eye_data_struct.gazeRight.x=naninterp(eye_data_struct.gazeRight.x);
            eye_data_struct.gazeRight.y=naninterp(eye_data_struct.gazeRight.y);
            eye_data_struct.gazeRight.x=lowPassFilter(bandpass,eye_data_struct.gazeRight.x,rate); %<<<=== rate ???
            eye_data_struct.gazeRight.y=lowPassFilter(bandpass,eye_data_struct.gazeRight.y,rate); %<<<=== rate ???
            eye_data_struct.gazeLeft.x=naninterp(eye_data_struct.gazeLeft.x);
            eye_data_struct.gazeLeft.y=naninterp(eye_data_struct.gazeLeft.y);
            eye_data_struct.gazeLeft.x=lowPassFilter(bandpass,eye_data_struct.gazeLeft.x,rate); %<<<=== rate ???
            eye_data_struct.gazeLeft.y=lowPassFilter(bandpass,eye_data_struct.gazeLeft.y,rate); %<<<=== rate ???
            
            function lowPassFilter=lowPassFilter(high,signal,rate)
                lowpass =high;
                if nargin < 3
                    rate = 1024;
                    warndlg(['assuming sampling rate of ' num2str(rate)])
                end

                % [nlow,Wnlow]=buttord((0.5*lowpass)/(0.5*rate), lowpass/(0.5*rate) , 0.01, 24);
                [nlow,Wnlow]=buttord( lowpass/(0.5*rate), min(0.999999, 2*lowpass/(0.5*rate)) , 3, 24); % Alon 27.1.09: changed so that high is the cuttoff freq of -3dB 
                %disp(['Wnlow = ' num2str(Wnlow)]);
                % [nlow,Wnlow]=buttord((0.5*lowpass)/(0.5*rate), lowpass/(0.5*rate) , 10, 18)

                [b,a] = butter(nlow,Wnlow,'low') ;
                lowPassFilter = filtfilt(b,a,signal);
                %figure; plot(signal); hold on;
                %plot(bandPassFilter);
            end
            
            function X = naninterp(X)                                         
                X(isnan(X)) = interp1(find(~isnan(X)), X(~isnan(X)), find(isnan(X)), 'PCHIP');            
            end            
        end
        
        function blinksbool= blinks_vec_gen(eyelink, delta, progress_screen, progress_contribution)
            if nargin==1
                delta=130;
            end

            exp_time= length(eyelink.gazeRight.time);
            blinksbool= zeros(1, exp_time);%initialize array matching the time points
            blinksbool=boolean(blinksbool);
            blinks_nr= length(eyelink.blinks.startTime);
            
            interval_blinks_nr= min(200,blinks_nr);
            interval_progress_contribution= progress_contribution*interval_blinks_nr/blinks_nr;
            for i= 1:blinks_nr
                if mod(i,interval_blinks_nr)==0
                    progress_screen.addProgress(interval_progress_contribution);
                end

                curr_start_time_i= find(eyelink.gazeRight.time==eyelink.blinks.startTime(i), 1);
                curr_end_time_i= find(eyelink.gazeRight.time==eyelink.blinks.endTime(i), 1);
                if curr_start_time_i-delta<1
                    curr_start_time_i= 1;
                else
                    curr_start_time_i= curr_start_time_i - delta;
                end

                if curr_end_time_i+delta>exp_time
                    curr_end_time_i= exp_time;
                else
                    curr_end_time_i= curr_end_time_i + delta;
                end

                blinksbool(curr_start_time_i:curr_end_time_i)=1;     
            end 
            
            if mod(blinks_nr,interval_blinks_nr)~=0
                progress_screen.addProgress(progress_contribution*mod(1,interval_blinks_nr/blinks_nr));
            end
        end               
    end
end

