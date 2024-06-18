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
        
        function summary = printf(self)
            N = numel(self.stack);
            summaryCell = cell(N,1);
            for ii=1:N
                
                stack = self.stack(ii);
                swaths = unique(stack.segments.swath);
                str = sprintf('Stack %i - %s, Orbit Number %i', ...
                    ii, ...
                    stack.reference.safeMeta.pass, ...
                    stack.reference.safeMeta.RON ...
                );
                for swathInd = swaths(:)'
                    str = sprintf('%s, Swath %i - Incidence Angle %.2f', ...
                        str, ...
                        swathInd, ...
                        stack.reference.safeMeta.swath(swathInd).incidenceAngle ...
                    ); %#ok<*PROP>
                end
                summaryCell{ii} = sprintf('%s\n',str);
            end
            summary = [summaryCell{:}];
        end

    end % methods


end % classdef