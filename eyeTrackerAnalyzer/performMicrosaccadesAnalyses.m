% //////////////////////////////////////////////////////////////////////////
% INPUT:
%   analysis_struct: cell array with a cell for each subject -> struct with
%   a field for each condition -> structure with field: onsets (matrix[n,t]:
%   n->number of trials, t->trial length), number of saccades (array[n]:
%   n-> number of trials),  amplitudes (under construction), directions
%   (current structure -> just a simple array of the saccades directions
% //////////////////////////////////////////////////////////////////////////
function [subjects_figs, statistisized_figs, analysis_struct_with_results]= performMicrosaccadesAnalyses(analysis_struct, exe_plot_curves, analyses, baseline, smoothing_window_len, trial_duration, progress_screen, progress_contribution)
    CURVES_COLORS= [1.0, 0.0, .0;  0.0, 1.0, 0.0;  0.0, 0.0, 1.0;  0.1, 0.1, 0.1;
        1.0, 1.0, 0.0;  1.0, 0.0, 1.0;  1, 0.7333, 0.0;  0.0, 1.0, 1.0;
        0.4, 0.8, 0.1;  0.4, 0.1, 0.8;  0.8, 0.4, 0.1;  0.8, 0.1, 0.4];   
    
    screen_size= get(0,'monitorpositions');    
    if any(screen_size(1,:)<0)
        screen_size= get(0,'ScreenSize');
    end    
    
    screen_size= screen_size(1,:);
    figure_positions= round([0.1*screen_size(3), 0.1*screen_size(4), 0.8*screen_size(3), 0.8*screen_size(4)]);
    conds_names= fieldnames(analysis_struct{1});
    conds_nr= numel(conds_names);
    if exe_plot_curves
        str_for_visible_prop= 'on';
    else
        str_for_visible_prop= 'off';
    end
    
    subjects_nr= numel(analysis_struct);
    subjects_figs= cell(2,2*sum(analyses),subjects_nr);
    analysis_struct_with_results.saccades_data= analysis_struct;
    analysis_struct_with_results.results_per_subject= cell(1, subjects_nr);
    analysis_struct_with_results.results_grand_total= [];
    
    % saccadic rate
    if analyses(1)                   
        max_trial_duration_per_cond = zeros(1, conds_nr);
        original_microsaccadic_rate = cell(1, conds_nr);
        smoothed_microsaccadic_rate = cell(1, conds_nr);
        for cond_i= 1:conds_nr                        
            for subject_i = 1:subjects_nr                
                if max_trial_duration_per_cond(cond_i) < size(analysis_struct{subject_i}.(conds_names{cond_i}).onsets, 2);
                   max_trial_duration_per_cond(cond_i) = size(analysis_struct{subject_i}.(conds_names{cond_i}).onsets, 2);
                end
            end
            original_microsaccadic_rate{cond_i} = NaN(subjects_nr, max_trial_duration_per_cond(cond_i));
            smoothed_microsaccadic_rate{cond_i} = NaN(subjects_nr, max_trial_duration_per_cond(cond_i) - smoothing_window_len);
        end
                        
        for subject_i= 1:subjects_nr
            curr_created_plots_nr= 0;
            if isempty(analysis_struct{subject_i})
                progress_screen.addProgress(0.9*progress_contribution/subjects_nr);
                continue;
            end           

            curr_created_plots_nr= curr_created_plots_nr + 1;
            %smooth window            
            smoothing_edge_left= floor(smoothing_window_len/2);
            smoothing_edge_right= ceil(smoothing_window_len/2);
            for cond_i= 1:conds_nr
                max_trial_duration = max_trial_duration_per_cond(cond_i);
                original_microsaccadic_rate{cond_i}(subject_i, 1:size(analysis_struct{subject_i}.(conds_names{cond_i}).onsets, 2)) = nanmean(analysis_struct{subject_i}.(conds_names{cond_i}).onsets, 1);
                smoothed_microsaccadic_rate_with_tails = smoothy( original_microsaccadic_rate{cond_i}(subject_i, 1:max_trial_duration), smoothing_window_len, progress_screen, 0.9*progress_contribution/(conds_nr*subjects_nr) );
                smoothed_microsaccadic_rate{cond_i}(subject_i, :) = smoothed_microsaccadic_rate_with_tails((smoothing_edge_left + 1):(max_trial_duration - smoothing_edge_right));
            end
           
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['microsaccades_rate_', num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','microsaccades_rate','NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
            for cond_i= 1:conds_nr                
                plot(((smoothing_edge_left + 1):(max_trial_duration_per_cond(cond_i) - smoothing_edge_right)) - baseline, ...
                       smoothed_microsaccadic_rate{cond_i}(subject_i,:), 'color', CURVES_COLORS(cond_i,:));
                analysis_struct_with_results.results_per_subject{subject_i}.saccadic_rate.(conds_names{cond_i})= smoothed_microsaccadic_rate{cond_i}(subject_i,:); 
                hold('on');
            end
            legend(conds_names);                        
            xlabel('Time [ms]');
            ylabel('Microsaccadic Rate [hz]');

            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['microsaccades_number_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','microsaccades_number','NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
            for cond_i= 1:conds_nr                
                stem(1:numel(analysis_struct{subject_i}.(conds_names{cond_i}).number_of_saccades), analysis_struct{subject_i}.(conds_names{cond_i}).number_of_saccades', 'color', CURVES_COLORS(cond_i,:));                 
                hold('on');
            end
            legend(conds_names);                        
        end
    else
        progress_screen.addProgress(0.9*progress_contribution);
    end

    % amplitude
    if analyses(2)
        for subject_i= 1:subjects_nr
            data_filled_conds_logical_vec= logical(true(numel(conds_names),1));
            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['amplitudes_by_condition_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','amplitudes by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);            
            for cond_i= 1:conds_nr                
                amplitudes= [analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}];
                if isempty(amplitudes)
                    data_filled_conds_logical_vec(cond_i)= false;
                    continue;
                end
                polar_h= polar([analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}], amplitudes, '.');
                set(polar_h, 'color', CURVES_COLORS(cond_i,:));
                hold('on');
            end
            if any(data_filled_conds_logical_vec)
                legend(conds_names{data_filled_conds_logical_vec});
            end

            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['amplitudes_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','amplitudes', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);            
            amplitudes= [];
            directions= [];
            if any(data_filled_conds_logical_vec)
                for cond_i= 1:conds_nr
                    amplitudes= [amplitudes, analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}]; %#ok<AGROW>
                    directions= [directions, analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}]; %#ok<AGROW>
                end

                polar(directions, amplitudes, '.');
            end
                        
            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['amplitudes_hist_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','amplitudes histogram', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);                   
            hist(amplitudes, 50);
            progress_screen.addProgress(0.033*progress_contribution/subjects_nr);
        end
    else
        progress_screen.addProgress(0.033*progress_contribution);
    end
        
    % directions
    if analyses(3)
        for subject_i= 1:subjects_nr
            data_filled_conds_logical_vec= logical(true(numel(conds_names),1));        
            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['directions_by_condition_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','directions by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
            polar(360,100);
            for cond_i= 1:conds_nr                
                directions= [analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}];
                if isempty(directions)
                    data_filled_conds_logical_vec(cond_i)= false;
                    continue;
                end
                rose_h= rose(directions);
                set(rose_h, 'color', CURVES_COLORS(cond_i,:));
                hold('on');
            end
            if any(data_filled_conds_logical_vec)                 
                legend(conds_names{data_filled_conds_logical_vec});             
            end

            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['directions_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','directions', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
            polar(360,200);
            directions= [];
            if any(data_filled_conds_logical_vec)
                for cond_i= 1:conds_nr
                    directions= [directions, analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}]; %#ok<AGROW>
                end

                rose(directions);
            end
            
            progress_screen.addProgress(0.033*progress_contribution/subjects_nr);
        end
    else
        progress_screen.addProgress(0.033*progress_contribution);
    end
        
    % main sequence
    if analyses(4)
        for subject_i= 1:subjects_nr
            data_filled_conds_logical_vec= logical(true(numel(conds_names),1));        
            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['main_sequence_by_condition_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','main sequence by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);            
            for cond_i= 1:conds_nr                
                amplitudes= [analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}];
                velocities= [analysis_struct{subject_i}.(conds_names{cond_i}).velocities{:}];
                if isempty(amplitudes) || isempty(velocities)
                    data_filled_conds_logical_vec(cond_i)= false;
                    continue;
                end
                plot_h= loglog(amplitudes, velocities, '.', 'MarkerSize', 5); 
                set(plot_h, 'color', CURVES_COLORS(cond_i,:));
                hold('on');
            end
            if any(data_filled_conds_logical_vec)                 
                legend(conds_names{data_filled_conds_logical_vec});             
            end

            curr_created_plots_nr= curr_created_plots_nr + 1;
            subjects_figs{1,curr_created_plots_nr,subject_i}= ['main_sequence_',num2str(subject_i)];
            subjects_figs{2,curr_created_plots_nr,subject_i}= figure('name','main sequence', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);            
            if any(data_filled_conds_logical_vec)
                velocities= [];
                amplitudes = [];            
                for cond_i= 1:conds_nr
                    velocities= [velocities, analysis_struct{subject_i}.(conds_names{cond_i}).velocities{:}]; %#ok<AGROW>
                    amplitudes= [amplitudes, analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}]; %#ok<AGROW>
                end

                loglog(amplitudes, velocities, '.k', 'MarkerSize', 5); 
            end
            [pearson_r, pearson_p_value] = corr(velocities',amplitudes');
            set(gca, 'title', text(0,0,['Pearson''s r = ', num2str(pearson_r), ', p-value = ', num2str(pearson_p_value)]));
            
            progress_screen.addProgress(0.034*progress_contribution/subjects_nr);
        end
    else
        progress_screen.addProgress(0.034*progress_contribution);
    end
    

    %CREATE GRAND AVERAGE PLOTS
    curr_created_plots_nr= 0;        
    
    % rate
    if analyses(1)
        curr_created_plots_nr= curr_created_plots_nr + 1;
        smoothed_grand_microsaccadic_rate= NaN(conds_nr, max_trial_duration_per_cond(cond_i) - smoothing_window_len);
        for cond_i= 1:conds_nr            
            curr_cond_original_grand_microsaccadic_rate= nanmean(original_microsaccadic_rate{cond_i}, 1);
            smoothed_grand_microsaccadic_rate_with_tails= smoothy( curr_cond_original_grand_microsaccadic_rate, smoothing_window_len, progress_screen, 0 );
            smoothed_grand_microsaccadic_rate(cond_i,:)= smoothed_grand_microsaccadic_rate_with_tails((smoothing_edge_left + 1):(max_trial_duration_per_cond(cond_i) - smoothing_edge_right));
        end

        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-microsaccades_rate';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: microsaccades rate', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
        for cond_i= 1:conds_nr            
            plot(((smoothing_edge_left + 1):(max_trial_duration_per_cond(cond_i) - smoothing_edge_right)) - baseline, smoothed_grand_microsaccadic_rate(cond_i,:), 'color', CURVES_COLORS(cond_i,:));
            analysis_struct_with_results.results_grand_total.saccadic_rate.(conds_names{cond_i})= smoothed_grand_microsaccadic_rate(cond_i,:);
            hold('on');
        end
        legend(conds_names);                       
        xlabel('Time [ms]');
        ylabel('Microsaccadic Rate [hz]');
    end

    % amplitude
    data_filled_conds_logical_vec= logical(true(numel(conds_names),1));
    if analyses(2)
        curr_created_plots_nr= curr_created_plots_nr + 1;
        grand_amplitudes= cell(1,conds_nr);
        grand_directions= cell(1,conds_nr);
        for cond_i=1:conds_nr
            grand_amplitudes{cond_i}= [];
            grand_directions{cond_i}= [];
            for subject_i= 1:subjects_nr
                grand_amplitudes{cond_i}= [grand_amplitudes{cond_i}, analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}];
                grand_directions{cond_i}= [grand_directions{cond_i}, analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}];
            end
        end

        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-amplitudes_by_condition';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: amplitudes by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);        
        for cond_i= 1:conds_nr            
            if isempty(grand_amplitudes{cond_i})
               data_filled_conds_logical_vec(cond_i)= false;
               continue;
            end
            polar_h= polar(grand_directions{cond_i}, grand_amplitudes{cond_i}, '.');            
            set(polar_h, 'color', CURVES_COLORS(cond_i,:));            
            hold('on');
        end        
        if any(data_filled_conds_logical_vec)                 
            legend(conds_names{data_filled_conds_logical_vec});             
        end

        curr_created_plots_nr= curr_created_plots_nr + 1;
        
        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-amplitudes';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: amplitudes ', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);        
        if any(data_filled_conds_logical_vec)                 
            grand_amplitudes_over_conditions= [];
            grand_directions_over_conditions= [];
            for cond_i=1:conds_nr
                grand_amplitudes_over_conditions= [grand_amplitudes{cond_i}, grand_amplitudes_over_conditions];	%#ok<AGROW>
                grand_directions_over_conditions= [grand_directions{cond_i}, grand_directions_over_conditions];	%#ok<AGROW>
            end
            polar(grand_directions_over_conditions, grand_amplitudes_over_conditions, '.');
        end
    end

    % directions
    data_filled_conds_logical_vec= logical(true(numel(conds_names),1));
    if analyses(3)
        curr_created_plots_nr= curr_created_plots_nr + 1;
        grand_directions= cell(1,conds_nr);
        for cond_i=1:conds_nr
            grand_directions{cond_i}= [];
            for subject_i= 1:subjects_nr
                grand_directions{cond_i}= [grand_directions{cond_i}, analysis_struct{subject_i}.(conds_names{cond_i}).directions{:}];
            end
        end

        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-directions_by_condition';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: directions by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
        polar(360,200);
        for cond_i= 1:conds_nr            
            if isempty(grand_directions{cond_i})
                data_filled_conds_logical_vec(cond_i)= false;
                continue;
            end
            rose_h= rose(grand_directions{cond_i});
            hold('on');
            set(rose_h, 'color', CURVES_COLORS(cond_i,:));
        end
        if any(data_filled_conds_logical_vec)                 
            legend(conds_names{data_filled_conds_logical_vec});             
        end 

        curr_created_plots_nr= curr_created_plots_nr + 1;
        
        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-directions';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: directions ', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);
        polar(360,200);        
        if any(data_filled_conds_logical_vec)
            grand_directions_over_conditions= [];
            for cond_i=1:conds_nr
                grand_directions_over_conditions= [grand_directions{cond_i}, grand_directions_over_conditions];	%#ok<AGROW>
            end
            rose(grand_directions_over_conditions);
        end
    end
    
    % main sequence
    data_filled_conds_logical_vec= logical(true(numel(conds_names),1));
    if analyses(4)
        curr_created_plots_nr= curr_created_plots_nr + 1;
        grand_velocities= cell(1,conds_nr);
        grand_amplitudes = cell(1,conds_nr);
        for cond_i=1:conds_nr
            grand_velocities{cond_i}= [];
            grand_amplitudes{cond_i} = [];
            for subject_i= 1:subjects_nr
                grand_velocities{cond_i}= [grand_velocities{cond_i}, analysis_struct{subject_i}.(conds_names{cond_i}).velocities{:}];
                grand_amplitudes{cond_i}= [grand_amplitudes{cond_i}, analysis_struct{subject_i}.(conds_names{cond_i}).amplitudes{:}];
            end
        end

        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-main_sequence_by_condition';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: main sequence by condition', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);        
        for cond_i= 1:conds_nr            
            if isempty(grand_velocities{cond_i}) || isempty(grand_amplitudes{cond_i})
                data_filled_conds_logical_vec(cond_i)= false;
                continue;
            end
            plot_h= loglog(grand_amplitudes{cond_i}, grand_velocities{cond_i}, '.', 'MarkerSize', 5); 
            set(plot_h, 'color', CURVES_COLORS(cond_i,:));
            hold('on');           
        end
        if any(data_filled_conds_logical_vec)                 
            legend(conds_names{data_filled_conds_logical_vec});             
        end 

        curr_created_plots_nr= curr_created_plots_nr + 1;
        
        statistisized_figs{1,curr_created_plots_nr}= 'grand_average-main_sequence';
        statistisized_figs{2,curr_created_plots_nr}= figure('name','grand average: main sequence ', 'NumberTitle', 'off', 'position', figure_positions, 'visible', str_for_visible_prop);               
        if any(data_filled_conds_logical_vec)
            grand_velocities_over_conditions= [];
            grand_amplitudes_over_conditions= [];
            for cond_i=1:conds_nr
                grand_velocities_over_conditions= [grand_velocities_over_conditions, grand_velocities{cond_i}];	%#ok<AGROW>
                grand_amplitudes_over_conditions= [grand_amplitudes_over_conditions, grand_amplitudes{cond_i}];	%#ok<AGROW>
            end
            loglog(grand_amplitudes_over_conditions, grand_velocities_over_conditions, '.k', 'MarkerSize', 5); 
        end
        [pearson_r, pearson_p_value] = corr(grand_velocities_over_conditions',grand_amplitudes_over_conditions');
        set(gca, 'title', text(0,0,['Pearson''s r = ', num2str(pearson_r), ', p-value = ', num2str(pearson_p_value)]));
    end
end