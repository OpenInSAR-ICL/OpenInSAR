classdef Stacks < OI.Data.DataObj
    properties
        generator = 'Stacking'
        stack = struct();
        id = 'Stacks'
    end % properties

    methods
        function this = Stacks(varargin)
            this.hasFile = true;
            this.filepath = '$workingDirectory$/stacks';
        end

        function tf = needs_load(this)
            tf = numel(fieldnames(this.stack)) == 0;
        end
        
        function info = get_reference_info(this, preprocInfo, stackInd, segmentInd)
            info = struct(...
                'safeIndex', [], ...
                'swathIndex', [], ...
                'burstIndex', [], ...
                'linesPerBurst', [], ...
                'samplesPerBurst', [], ...
                'swathInfo', struct());
                
            % Get metadata for reference
            info.safeIndex = this.stack(stackInd).segments.safe( segmentInd );
            info.swathIndex = this.stack(stackInd).segments.swath( segmentInd );
            info.burstIndex = this.stack(stackInd).segments.burst( segmentInd );
            info.swathInfo = ...
                preprocInfo.metadata(info.safeIndex).swath(info.swathIndex);

            % Size of reference data array
            [info.linesPerBurst, info.samplesPerBurst, ~, ~] = ...
                OI.Plugins.Geocoding.get_parameters( info.swathInfo );
        end

    end % methods


end % classdef