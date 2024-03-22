classdef PersistentScatterersInversion < OI.Plugins.PluginBase
    %#ok<*NASGU>
    %#ok<*AGROW>
    properties
        inputs = {OI.Data.ApsModel(), OI.Data.BlockPsiSummary()}
        outputs = {OI.Data.PersistentScatterersInversionSummary()}
        id = 'PersistentScatterersInversion'
        STACK = []
        BLOCK = []
    end

    methods

        function this = PersistentScatterersInversion(varargin)
            this.isArray = true;
            this.isFinished = false;
        end

        function this = run(this, engine, varargin)
            PHASE_TO_M_PER_A = 4 * pi / (365.25 .* 0.055);
            normz = @(x) x./abs(x);

            %% LOAD INPUTS
            blockMap = engine.load(OI.Data.BlockMap());
            projObj = engine.load(OI.Data.ProjectDefinition());

            % Exit if we're missing inputs
            if isempty(projObj) || isempty(blockMap)
                return
            end

            % Queue up all stacks jobs if we've not been told what to do
            if isempty(this.STACK) || isempty(this.BLOCK)
                this = this.queue_jobs(engine, blockMap);
                return
            end

            % Generate the output structs
            blockObj = OI.Data.Block().configure( ...
                'POLARISATION', 'VV', ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(this.BLOCK) ...
            );
            resultObj_C = OI.Data.BlockResult(blockObj, 'PSI_coherence').identify(engine);
            resultObj_v = OI.Data.BlockResult(blockObj, 'PSI_velocity').identify(engine);
            resultObj_q = OI.Data.BlockResult(blockObj, 'PSI_heightError').identify(engine);

            % Generate the shp name
            shpName = OI.Functions.generate_shapefile_name(this, projObj);

            % Check if we're done already
            if ~this.isOverwriting && exist(shpName, 'file') && resultObj_v.exists()
                this.isFinished = true;
                return;
            end

            % load geocoding
            blockGeocode = OI.Data.BlockGeocodedCoordinates().configure( ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(blockMap.stacks(this.STACK).blocks(this.BLOCK).index) ...
            );
            bg = engine.load(blockGeocode);
            if isempty(bg)
                return
            end

            % load APS
            apsModel =engine.load( OI.Data.ApsModel2().configure('STACK',this.STACK) );
            aps = apsModel.interpolate( bg.lat(:), bg.lon(:), bg.ele(:) );

            % Load block info
            stackBlocks = blockMap.stacks(this.STACK);
            blockInfo = stackBlocks.blocks(this.BLOCK);
            pAzAxis = blockInfo.azOutputStart:blockInfo.azOutputEnd;
            pRgAxis = blockInfo.rgOutputStart:blockInfo.rgOutputEnd;
            [pRgGrid, pAzGrid] = meshgrid(pRgAxis, pAzAxis);

            % Load block baseline info
            baselinesObjectTemplate = OI.Data.BlockBaseline().configure( ...
                'STACK', num2str(this.STACK), ...
                'BLOCK', num2str(this.BLOCK) ...
            ).identify(engine);
            baselinesObject = engine.load(baselinesObjectTemplate);
            if isempty(baselinesObject)
                return
            end

            % Load the block SAR data
            blockData = engine.load(blockObj);
            if isempty(blockData)
                return
            end
            sz = size(blockData);
            blockData = reshape(blockData, [], sz(3));
%             missingData = sum(blockData) == 0;
%             blockData = blockData(:, ~missingData);
%             apsEst = apsEst(:, ~missingData);
%             apsModel.referencePhase = apsModel.referencePhase(~missingData);
%             % load block
%             apsInterpolation = zeros(size(blockData));
%             normz = @(x) OI.Functions.normalise(x);
%             for ii = 1:size(blockData, 2)
%                 tempApsInterp = interp2(apsModel.rgGrid, apsModel.azGrid, reshape(apsEst(:, ii), size(apsModel.rgGrid, 1), size(apsModel.rgGrid, 2), []), pRgGrid(:), pAzGrid(:));
%                 tempApsInterp(isnan(tempApsInterp)) = 0;
%                 apsInterpolation(:, ii) = tempApsInterp;
%                 blockData(:, ii) = blockData(:, ii) .* conj(apsInterpolation(:, ii));
%             end
% 
%             blockData = normz(blockData .* conj(apsModel.referencePhase));

            blockData = normz( blockData .* conj( aps ) );
            
            % remove low pass
            displacement = movmean(blockData, 11, 2);
            displacement = normz(displacement);
            blockData = blockData .* conj(displacement);

            % estimate height error
            [~, q] = OI.Functions.invert_height(blockData, baselinesObject.k(:)');

            % remove height error, add low pass back on
            blockData = displacement .* blockData .* exp(1i .* q .* baselinesObject.k(:)');
            blockData = normz(blockData);

            % estimate v
            [Cv, v] = OI.Functions.invert_velocity(blockData, baselinesObject.timeSeries(1, :) .* PHASE_TO_M_PER_A);
            % v is backwards for some reason
            v = -v;
            
            % Save the PSI outputs
            C0 = reshape(Cv, sz(1:2));
            v0 = reshape(v, sz(1:2));
            q0 = reshape(q, sz(1:2));
            engine.save(resultObj_C, C0);
            engine.save(resultObj_v, v0);
            engine.save(resultObj_q, q0);

            % Threshold for writing SHP
            MASK = Cv > .4;

            % So disp - exp(1i v) is the residual
            res = displacement(MASK, :) .* conj(displacement(MASK, round(mean(size(displacement, 2)))));
            res = res .* conj(normz(mean(res)));

            % Remove v and unwrap
            res = res .* exp(-1i .* baselinesObject.timeSeries(1, :) .* PHASE_TO_M_PER_A .* v(MASK));
            res = res .* conj(normz(mean(res, 2)));
            res = res .* conj(normz(mean(res)));
            uwres = unwrap(angle(res)')';
            uwres = uwres - uwres(:, 1);
            uwres = uwres .* (0.055 ./ (4 * pi));

            datestrCells = cell(length(baselinesObject.timeSeries), 1);
            for ii = 1:length(baselinesObject.timeSeries)
                datestrCells{ii} = datestr(baselinesObject.timeSeries(1, ii), 'YYYYmmDD');
            end

            % // free some mem
            blockData = [];
            apsInterpolation = [];
            displacement = [];
            pscNoAps = [];
            pscNoApsNoQ = [];
            pscNoApsNoDisp = [];
            pscPhi = [];
            res = [];

            % Write preview KMLs
            mask0s = @(A) OI.Functions.mask0s(A);
            if baselinesObject.azimuthVector(3) > 0 % ascending
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(flipud(Cv)), 'Coherence', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(flipud(v .* mask0s(MASK))), 'Velocity', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(flipud(q .* mask0s(MASK))), 'HeightError', '1');
            else % descending
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(Cv), 'Coherence', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(v .* mask0s(MASK)), 'Velocity', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(q .* mask0s(MASK)), 'HeightError', '1');
            end

            OI.Functions.ps_shapefile( ...
                shpName, ...
                bg.lat(MASK), ...
                bg.lon(MASK), ...
                uwres, ... % displacements 2d Array
                datestrCells, ... % datestr(timeSeries(1),'YYYYMMDD')
                q(MASK), ...
                v(MASK), ...
                Cv(MASK));

            this.isFinished = true;

        end % run

        function this = queue_jobs(this, engine, blockMap)
            allDone = true;
            jobCount = 0;

            % Queue up all blocks
            for stackIndex = 1:numel(blockMap.stacks)
                stackBlocks = blockMap.stacks(stackIndex);
                for blockIndex = stackBlocks.usefulBlockIndices(:)'
                    blockInfo = stackBlocks.blocks(blockIndex);
                    % Create the result template
                    blockObj = OI.Data.Block().configure( ...
                        'STACK', num2str(stackIndex), ...
                        'BLOCK', num2str(blockIndex) ...
                    );
                    resultObj = OI.Data.BlockResult(blockObj, 'PSI_coherence').identify(engine);

                    % Check if the block is already done
                    priorObj = engine.database.find(resultObj);

                    if isempty(priorObj)
                        jobCount = jobCount + 1;
                        engine.requeue_job_at_index( ...
                            jobCount, ...
                            'STACK', stackIndex, ...
                            'BLOCK', blockIndex ...
                        );
                        allDone = false;
                    end
                end
            end

            if allDone
                this.isFinished = true;
                engine.save(this.outputs{1})
            end

        end % queue_jobs

    end % methods

end % classdef
