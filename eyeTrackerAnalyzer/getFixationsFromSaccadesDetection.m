function [fix_struct]=getFixationsFromSaccadesDetection(d,onsets ,offsets ,amplitudes, toocloseThresh,blink_padding)
ENUM_ONSET_TYPES_SACCADE = 1;
ENUM_ONSET_TYPES_BLINK = 3;
ENUM_OFFSET_TYPES_SACCADE = 2;
ENUM_OFFSET_TYPES_BLINK = 4;

% fixation_onset_type: 
% 2 - fixation started with the end of the saccade
% 4 - fixation started with the end of a blink 
%fixation offset_types: 
% 1 - fixation ended with a start of a saccade
% 3 - fixation ended with the start of a blink 
% 5 - fixation ended with segment end.


%this code uses the detected saccades/ms paramaters and create a fixation
%input paramaters:

%  d - is the raw data structure used in ms/saccade detection:

%  the saccade offset is the fixation onset

%  saccade onset is fixation offset

%  Hcoords is the mean position from fixation start to end on the X axis

%  Vcoords is the mean position from the fixation start to end on the y axis

%  toocloseThresh is the minimum duration required between saccade end and
%  saccade start (default is 20ms).
% blink_padding - what was the parmater used to padd blinks (so it can be
% reduced to find the correct onset and offset of the blinks

% d should be structured as follows = [(1:length(dataXR))' dataXR' dataYR' dataXL' dataYL' blinksseg];

%note that if you want to maintain fixations if they had a small saccade in
%between, or if they had a blink in between - you can use the amplitudes
%vector (as nans would mean that this is a fixation that ended with a blink
%start) - so you can concatinate it with the following saccade.

%same can be done with the onset, if the fixation onset type is 4 - it
%started with a blink end. if fixation offset is 3 - it ended with a blink
%start (so you can concatinate those fixations).


to_plot=0; %change this if you want to see the trace with the detected saccade onsets

Nonsets=[];
Noffsets=[];


if to_plot
    %test plot:
    figure();
    plot(d(:,2:5));
    hold on;
    plot(d(:,6)*1000);
    hold on
    plot([onsets; onsets],repmat([0 2000],length(onsets),1)','r')
    plot([offsets; offsets],repmat([0 2000],length(offsets),1)','g')
end

if isempty(toocloseThresh)
    toocloseThresh=20;
end

if isempty(blink_padding)
    blink_padding=130;
end

%reduce 50ms from blink_padding, to be sure not to catch the end or start of
%the blink (position).
blink_padding=blink_padding-50;

%% add a fixation offset at the beggning of each blink, and an offset at the end of it:
blink_interval_onsets= find((diff(d(:,6)))==1)+blink_padding;
blink_interval_offsets=find((diff(d(:,6)))==-1)-blink_padding;


types=ones(1,length(onsets));
amps=amplitudes;
if ~isempty(blink_interval_onsets)
    types=[types,ones(1,length(blink_interval_onsets))*3];
    onsets=[onsets;blink_interval_onsets];
end

types=[types,ones(1,length(offsets))*2];

if ~isempty(blink_interval_offsets)
    types=[types,ones(1,length(blink_interval_offsets))*4];
    offsets=[offsets;blink_interval_offsets];    
end

all_timings=[onsets;offsets];
amps=[amps',nan(1,length(all_timings)-length(amps))];

[sorted_timings,sorting_indexes]=sort(all_timings,'ascend');
sorted_timings = sorted_timings';
sorted_types=types(sorting_indexes);
sorted_amps=amps(sorting_indexes);

% %fix sorted types: (not working yet)
% types_alternation=mod(sorted_types,2); %(should alternate between an event onset (1 or 3) and event offset( 2 or 4)
% %if types are not alternating, find the positions and delete the earlier
% %one
% suspected_bad_detections=find(diff(types_alternation)==0);
% timing_differences=sorted_timings(suspected_bad_detections+1)-sorted_timings(suspected_bad_detections)
% suspected_bad_detections_types=sorted_types(suspected_bad_detections);


%correct the specific case of a blink encapsulated by saccades:
saccades_surounding_blinks= strfind(sorted_types,[1 3 4 2]);
if ~isempty(saccades_surounding_blinks)
    bad_s_inds=[saccades_surounding_blinks,saccades_surounding_blinks+3];
    sorted_types(bad_s_inds)=[];
    sorted_amps(bad_s_inds)=[];
    sorted_timings(bad_s_inds)=[];
end




%1 is a saccade onset, 3% blink onset
%2 saccade offset, 4 blink offset

%a blink/saccade offset is a fixation onset:
%find the first offset in the trial (which will be the first fixation
%onset)
first_fix_onset_ind=find(sorted_types==2 | sorted_types==4,1,'first');
last_fix_offset_ind=find(sorted_types==1 | sorted_types==3,1,'last');

Nonsets=sorted_timings(first_fix_onset_ind:2:last_fix_offset_ind)';
Nonsettypes=sorted_types(first_fix_onset_ind:2:last_fix_offset_ind)';


%get information on the last fixation on the segment:

last_fixation_onset=find(sorted_types==2 | sorted_types==4,1,'last');
if ~isempty(last_fixation_onset)
    last_onset_type=sorted_types(last_fixation_onset);
    last_onset_timing=sorted_timings(last_fixation_onset);
    
    if ~isempty(Nonsets) && last_onset_timing>Nonsets(end)
        
        last_offset_type=5;
        last_onset_offtiming=length(d(:,2));
        last_fixation_duration=nan;
    else
        last_onset_type=[];
        last_onset_timing=[];
        last_offset_type=[];
        last_onset_offtiming=[];
        last_fixation_duration=[];
    end
else
    last_onset_type=[];
    last_onset_timing=[];
    last_offset_type=[];
    last_onset_offtiming=[];
    last_fixation_duration=[];
end
%check for problems:
if any(mod(Nonsettypes,2)~=0) %is there an onset type that is not a blink or a saccade end
    disp('possible problem')
    Nonsets(mod(Nonsettypes,2)~=0)=[];
    Nonsettypes(mod(Nonsettypes,2)~=0)=[];
end



Noffsets=sorted_timings(first_fix_onset_ind+1:2:last_fix_offset_ind)';
Noffsettypes=sorted_types(first_fix_onset_ind+1:2:last_fix_offset_ind)';
Namplitudes=sorted_amps(first_fix_onset_ind+1:2:last_fix_offset_ind)';

if any(mod(Noffsettypes,2)~=1)
    disp('possible problem')
    Noffsets(mod(Noffsettypes,2)~=1)=[];
    Noffsettypes(mod(Noffsettypes,2)~=1)=[];
end

if to_plot
    %test plot:
    figure();
    plot(d(:,2:5));
    hold on;
    plot(d(:,6)*1000);
    hold on
    plot([Nonsets; Nonsets],repmat([0 2000],length(Nonsets),1)','r')
    plot([Noffsets; Noffsets],repmat([0 2000],length(Noffsets),1)','g')
    if ~isempty(last_onset_timing)
        hold on
        plot([last_onset_timing;last_onset_timing],[0 2000],'r');
        hold on
    end
    
end


NH_coords=[];
NV_coords=[];
disperity_V=[];
disperity_H=[];
disperity_Vabs=[];
disperity_Habs=[];

if ~isempty(Nonsets) && ~isempty(Noffsets)
    if Nonsets(end)>Noffsets(end)
        Nonsets(end)=[];
    end
    Ndurations=Noffsets-Nonsets;
else
    Ndurations=[];
end

Nonsets=[Nonsets;last_onset_timing];
Noffsets=[Noffsets;last_onset_offtiming];
Ndurations=[Ndurations;last_fixation_duration];
Nonsettypes=[Nonsettypes;last_onset_type];  %i just changed this from "last_offset_type"
Noffsettypes=[Noffsettypes;last_offset_type];



for i=1:length(Nonsets);
    %get the mean right eye horz position during fixation
    if Noffsets(i)>size(d,1);
        Noffsets(i)=size(d,1);
    end
    
    if Nonsets(i)<=0
        Nonsets(i)=1;
    end
    
    tempd=d;
    tempd(d(:,6)==1,2:5)=nan;
    
    
    
    HR_mean=nanmean(tempd(Nonsets(i):Noffsets(i),2));
    %get the mean left eye horz position during fixation
    HL_mean=nanmean(tempd(Nonsets(i):Noffsets(i),4));
    %average the two eyes on the horz dimention
    NH_coords(i)=mean([HR_mean,HL_mean]);
    disperity_H(i)=mean(tempd(Nonsets(i):Noffsets(i),2)-tempd(Nonsets(i):Noffsets(i),4));
    disperity_Habs(i)=mean(abs(tempd(Nonsets(i):Noffsets(i),2)-tempd(Nonsets(i):Noffsets(i),4)));
    
    
    %get the mean right eye vert position during fixation
    VR_mean=nanmean(tempd(Nonsets(i):Noffsets(i),3));
    %get the mean left eye vert position during fixation
    VL_mean=nanmean(tempd(Nonsets(i):Noffsets(i),5));
    %average the two eyes on the vert dimention
    NV_coords(i)=mean([VR_mean,VL_mean]);
    disperity_V(i)=mean(tempd(Nonsets(i):Noffsets(i),3)-tempd(Nonsets(i):Noffsets(i),5));
    disperity_Vabs(i)=mean(abs(tempd(Nonsets(i):Noffsets(i),3)-tempd(Nonsets(i):Noffsets(i),5)));
end

%build output structure
fix_struct.onsets=Nonsets;
fix_struct.offsets=Noffsets;
fix_struct.Hpos=NH_coords;
fix_struct.Vpos=NV_coords;
fix_struct.onset_types=Nonsettypes;
fix_struct.offset_types=Noffsettypes;
fix_struct.amplitudes=[Namplitudes;nan];
fix_struct.durations=Ndurations;
fix_struct.disperity_V=disperity_V;
fix_struct.disperity_Vabs=disperity_Vabs;
fix_struct.disperity_H=disperity_H;
fix_struct.disperity_Habs=disperity_Habs;


end