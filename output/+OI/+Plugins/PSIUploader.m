classdef PSIUploader < OI.Plugins.PluginBase
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

        function this = PSIUploader(varargin)
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
            resultObj_U =  OI.Data.BlockResult(blockObj, 'Uploaded').identify(engine);
            % set overwrite
            resultObj_C.overwrite = this.isOverwriting;
            resultObj_v.overwrite = this.isOverwriting;
            resultObj_q.overwrite = this.isOverwriting;

            % Generate the shp name
            shpName = OI.Functions.generate_shapefile_name(this, projObj);

            % Check if we're done already
            if ~this.isOverwriting && exist(shpName, 'file') && resultObj_U.exists()
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
            apsModel =engine.load( OI.Data.ApsModel3().configure('STACK',this.STACK) );
            if isempty(apsModel)
                return
            end
            
            [dy, dx]=OI.Functions.haversineXY([bg.lat(:) bg.lon(:)],apsModel.referenceLLE);
            aps = apsModel.interpolate( dy, dx, bg.ele(:), 1 );
            aps(isnan(aps)) = 1;  % remove out of bounds nans, set to 0 phase
            
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

            ts = baselinesObject.timeSeries(1, :);
            ts = ts - ts(:,1);
            tsp = ts .* PHASE_TO_M_PER_A;
            % tsp = tsp - tsp(:,1);

            k = baselinesObject.k(:)';

            % Load the block SAR data
            blockData = engine.load(blockObj);
            if isempty(blockData)
                return
            end
            
            sz = size(blockData);
            mask0s = @(A) OI.Functions.mask0s(A);
            r2d = @(x) reshape(x, sz(1:2));
            dm2 = @(x) x.*conj(mean(x,2));

            blockData = reshape(blockData, [], sz(3));
            
            mu = mean(abs(blockData),2);
            sigma = var(abs(blockData),0,2).^.5;
            as = mu./sigma;
            
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
            
            % Remove residual low pass offset/ambiguity from aps model
            % m = normz(mean(dm2(blockData)));
            % blockData = blockData .* conj(m);
            % TODO THE ABOVE SHOULD BE DONE IN APS, WHERE IS ERROR INTRODUCED?
 
            % remove low pass
            displacement = movmean(blockData, 11, 2);
            displacement = normz(displacement);
            blockData = blockData .* conj(displacement);

            % estimate height error
            [~, q] = OI.Functions.invert_height(blockData, k,120,121);

            % remove height error, add low pass back on
            blockData = blockData .* exp(1i .* q .* baselinesObject.k(:)');
            
            % before we add any low pass back on, remove any constants
            % (aps)
            m = normz(mean(dm2(blockData)));
            blockData = blockData .* conj(m);
            blockData = blockData .* displacement;
            blockData = normz(blockData);

            % estimate v
            [Cv, v] = OI.Functions.invert_velocity(blockData, tsp, 0.05, 101);
            % update residual
            blockData = blockData .* exp( 1i * ( v .* tsp ));
            
            % v is backwards for some reason
            v = -v;
            % POSITIVE (RED) IS SUBSIDENCE
            
            % Save the PSI outputs
            C0 = reshape(Cv, sz(1:2));
            v0 = reshape(v, sz(1:2));
            q0 = reshape(q, sz(1:2));
            engine.save(resultObj_C, C0);
            engine.save(resultObj_v, v0);
            engine.save(resultObj_q, q0);

            % update residual
%             blockData = blockData .* exp( - 1i * ( v .* tsp ));


            % Threshold for writing SHP
            MASK = Cv > .4 & as(:) > 1.75;

            % Estimate residual deformation
            nld = movmean(blockData(MASK,:), 21, 2);
            nld = nld .* conj(mean(nld,2));

            % unwrap
            unld = unwrap(angle(nld),[],2);

            % add vel back on
            real_displacement_m = -unld * 0.055 / ( 4 * pi ) - v(MASK) .* ts / 365;
            real_displacement_m = real_displacement_m - real_displacement_m(:,1); % start at 0.
            
            datestrCells = cell(length(baselinesObject.timeSeries), 1);
            for ii = 1:length(baselinesObject.timeSeries)
                datestrCells{ii} = datestr(baselinesObject.timeSeries(1, ii), 'YYYYmmDD');
            end

            % free some mem
            blockData = [];
            apsInterpolation = [];
            displacement = [];
            pscNoAps = [];
            pscNoApsNoQ = [];
            pscNoApsNoDisp = [];
            pscPhi = [];
            res = [];

            % Write preview KMLs
%             stacks = engine.load( OI.Data.Stacks() );
%             direction = stacks.stack(this.STACK).reference.safeMeta.pass;
            if baselinesObject.azimuthVector(3) > 0 % ascending
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, flipud(r2d(Cv)), 'Coherence', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, flipud(r2d(v .* mask0s(MASK))), 'Velocity', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, flipud(r2d(q .* mask0s(MASK))), 'HeightError', '1');
            else % descending
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(r2d(Cv)), 'Coherence', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(r2d(v .* mask0s(MASK))), 'Velocity', '1');
                OI.Plugins.BlockPsiAnalysis.preview_block(projObj, ...
                    blockInfo, fliplr(r2d(q .* mask0s(MASK))), 'HeightError', '1');
            end


            make_point = @(dataset_id, lat, lon, disp_ts, C, v, q) struct(...
                'dataset', dataset_id, ...
                'location', [lat, lon], ...
                'time_series_values', disp_ts, ...
                'coherence', C, ...
                'velocity', v, ...
                'height_error', q ...
            );
            Css = Cv(MASK);
            vss = v(MASK);
            qss = q(MASK);
            lat = bg.lat(MASK);
            lon = bg.lon(MASK);
            nPoints = length(lat);  % Total number of points
            

            BATCH = 1000;
            ROOT_URL = projObj.ROOT_URL;
            
            datasetId = OI.Functions.get_dateset_id(engine,ROOT_URL,this.STACK,this.BLOCK);
            % datasetIdStr = num2str(datasetId);
        
            authorised_request = OI.Functions.get_authorised_request(ROOT_URL, 'stew', '4040');
            startTime=tic;
            % POST data in batches
            for batch_start = 1:BATCH:nPoints
                S = struct('dataset', {}, 'location', {}, 'time_series_values', {}, 'coherence', {}, 'velocity', {}, 'height_error', {});
                batch_end = min(batch_start + BATCH - 1, nPoints);  % Ensure the last batch doesn't go out of bounds
                batch_size = batch_end - batch_start + 1;
            
                % Create a batch of points
                for ii = batch_end:-1:batch_start
                    S(ii - batch_start + 1) = make_point(datasetId, lat(ii), lon(ii), real_displacement_m(ii,:), Css(ii), vss(ii), qss(ii));
                end
            
                % Send the batch in the request
                response = OI.Functions.send_repeat_authorised_request(authorised_request, ROOT_URL, 'psi-info-upload/', S, false);
            
                % Check the response status and throw an error if not "Created"
                if ~strcmpi(response.StatusCode, 'Created')
                    error('Request failed with status: %s', response.StatusLine);
                end
                elapsedTime= toc(startTime);
                nDone = batch_end;
                nRemaining = nPoints - nDone;
                samplesPerSecond = nDone/elapsedTime;
                timeRemaining = nRemaining / samplesPerSecond;

                disp([sprintf('%i mins remaining.',round(timeRemaining./60)) ' Batch from ' num2str(batch_start) ' to ' num2str(batch_end) ' of ' num2str(nPoints) ' sent.']);
                
            end

            % OI.Functions.ps_shapefile( ...
            %     shpName, ...
            %     bg.lat(MASK), ...
            %     bg.lon(MASK), ...
            %     real_displacement_m, ... % displacements 2d Array
            %     datestrCells, ... % datestr(timeSeries(1),'YYYYMMDD')
            %     q(MASK), ...
            %     -v(MASK), ...
            %     Cv(MASK));

            engine.save(OI.Data.BlockResult(blockObj, 'Uploaded'))

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
                    resultObj = OI.Data.BlockResult(blockObj, 'Uploaded').identify(engine);

                    % Check if the block is already done
                    priorObj = engine.database.find(resultObj);

                    if isempty(priorObj) || ~priorObj.exists
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
