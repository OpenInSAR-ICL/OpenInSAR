classdef GeoTiffs < OI.Plugins.PluginBase
    
properties
    inputs = {OI.Data.CoregistrationSummary()}
    outputs = {OI.Data.GeotiffSummary()}
    id = 'GeoTiffs'
    STACK = []
    VISIT = []
    SEGMENT = []
    AOI = []
    SIZE = [] % [x y] pixels
    MAPPING_AVAILABLE = false;
    TYPE = {'VV', 'VH', 'VV_COHERENCE', 'VH_COHERENCE'}
end

methods
    function this = GeoTiffs( varargin )
        this.isArray = true;
        this.isFinished = false;
    end    


    function this = run(this, engine, varargin)
        stacks = engine.load( OI.Data.Stacks() );
        coregDone = engine.load(this.inputs{1});
        projObj = engine.load( OI.Data.ProjectDefinition() );
        stitchInfo = engine.load( OI.Data.StitchingInformation );
        % If required inputs are missing, return
        if isempty(stacks) || isempty(coregDone) || isempty(stitchInfo)
            return
        end
        
        % If array job parameters are not set, generate and paramaterise new jobs
        if isempty(this.STACK)
            this = this.queue_jobs(engine, stacks);
            return;
        end

        % If no AOI is specified, use the overall project AOI
        if isempty(this.AOI)
            this.AOI = projObj.AOI;
        end

        % If no size is specified, use a resolution approximately equivalent to the raw data
        if isempty(this.SIZE)
            dLon = this.AOI.eastLimit - this.AOI.westLimit;
            dLat = this.AOI.northLimit - this.AOI.southLimit;
            
            approxWidthMeters = (dLon/360) * 40075e3 * ... % circ of earth
                cosd(this.AOI.southLimit + dLat/2); % adj for lat, use mean
            approxHeightMeters = (dLat/360) *  40008e3; % circ of earth at poles
            pixH = approxHeightMeters/12;
            pixW = approxWidthMeters/3;
            this.SIZE = round([pixH, pixW]);
        end

        % If the mapping has not been calculated, calculate it and then generate new jobs
        if isempty(this.MAPPING_AVAILABLE) || ~this.MAPPING_AVAILABLE
            if isempty(this.SEGMENT)
                warning([ ...
                'The object does not know whether not the mapping files are available, set MAPPING_AVAILABLE to true/false.\n' ...
                'Additionally no ''SEGMENT'' has been provided as a target for mapping.\n' ...
                'The plugin will proceed assuming that mapping files are available (and fail fairly quickly if not).\n' ...
                ])
            else
                this = this.generate_mapping(engine, stacks);
                return;
            end    
        end
        
        if isempty(this.VISIT)
            error('Object does not know what to do. Please instruct which VISIT to process.')
        end

        % TODO this info should now be in STACKS object
        cat = engine.load(OI.Data.Catalogue() );
        thisStack = stacks.stack(this.STACK);
        % load the mapping data
        segments = thisStack.reference.segments.index;
        firstSeg = find(thisStack.correspondence(:,this.VISIT),1);
        if isempty(firstSeg)
            warning('No valid data for this date, in this stack and segment');
            return
        end
        segmentInd = thisStack.correspondence(firstSeg,this.VISIT);
        safeInd = thisStack.segments.safe(segmentInd);
        visitDatestr = cat.safes{safeInd}.date.datestr;
        
        geoTiffObj = OI.Data.GeoTiff().configure( ...
            'STACK', this.STACK, ...
            'VISIT', this.VISIT, ...
            'DATE', visitDatestr);

        % TODO this should go in types loop? line-108?
        % Allocate the output raster
        output = zeros(this.SIZE);
        
        % define the output grid
        oGrid = this.generate_grid(this.AOI, this.SIZE);
        tiffMeta = this.get_geotiff_metadata( oGrid.latGrid, oGrid.lonGrid, this.SIZE);

        mappingCells = this.load_mapping( engine, thisStack );
        
        preprocessingInfo = engine.load( OI.Data.PreprocessedFiles() );
        avfilt = @(x) imfilter(x, fspecial('average', [4, 20]));
        
        % loop through different products
        for typeCell = this.TYPE
            % Overwrite data if the current segment has closer data.
            betterSamples = false(this.SIZE);
            currentDistance = inf.*ones(this.SIZE);
            
            for segInStack = 1:numel(segments)
                this.SEGMENT = segments(segInStack);
                mapping = mappingCells{segInStack};
                stitch = stitchInfo.stack(this.STACK);
                validSamples = stitch.segments(segInStack).validSamples;
                %% We need to deramp the data as we're resampling it.
                
                % get general info and metadata
                % address of the data in the catalogue and metadata
                segInCatalogue = stacks.stack(this.STACK).correspondence(this.SEGMENT, this.VISIT);
                
                % If no data for this seg/visit, move on
                if ~segInCatalogue
                    continue
                end
                
                safeIndex = stacks.stack(this.STACK).segments.safe( segInCatalogue );
                safe = cat.safes{safeIndex};
                swathIndex = stacks.stack(this.STACK).segments.swath( segInCatalogue );
                burstIndex = stacks.stack(this.STACK).segments.burst( segInCatalogue );
                swathInfo = ...
                    preprocessingInfo.metadata( safeIndex ).swath( swathIndex );
                
                % Get reference geometry and metadata
                refSafeIndex = stacks.stack(this.STACK).segments.safe( this.SEGMENT );
                refSwathIndex = stacks.stack(this.STACK).segments.swath( this.SEGMENT );
                refBurstIndex = stacks.stack(this.STACK).segments.burst( this.SEGMENT );
                refSwathInfo = ...
                    preprocessingInfo.metadata(refSafeIndex).swath(refSwathIndex);
                % Size of reference data array
                [lpbRef,spbRef,~,~] = ...
                    OI.Plugins.Geocoding.get_parameters( refSwathInfo );
                [refMeshRange, refMeshAz] = ...
                    OI.Plugins.Geocoding.get_geometry(lpbRef,spbRef);
                refSz = [lpbRef, spbRef];
                % Size of this data
                [lpb,spb,nearRange,rangeSampleDistance] = ...
                    OI.Plugins.Geocoding.get_parameters( swathInfo );
                [meshRange, meshAz] = ...
                    OI.Plugins.Geocoding.get_geometry(lpb,spb);
        
                % get coreg offsets
                result = OI.Data.CoregOffsets().configure( ...
                    'STACK', num2str(this.STACK), ...
                    'REFERENCE_SEGMENT_INDEX', num2str(this.SEGMENT), ...
                    'VISIT_INDEX', num2str(this.VISIT)).identify( engine );
                azRgOffsets = engine.load( result );
                if isempty(azRgOffsets)
                    return % no input coreg data
                end
                a = reshape(azRgOffsets(:,1),refSz);
                r = reshape(azRgOffsets(:,2),refSz);
                clearvars azRgOffsets
                
                % get orbit
                [orbit, lineTimes] = ...
                    OI.Plugins.Geocoding.get_poe_and_timings( ...
                        cat, safeIndex, swathInfo, burstIndex );
                    
                % centre the orbit line times
                orbitCentre = mean(lineTimes);
                orbit.t = orbit.t - orbitCentre;
                    
                % deramp
                [derampPhase, ~, azMisregistrationPhase] = ...
                    OI.Functions.deramp_demod_sentinel1( ...
                    swathInfo, burstIndex, orbit, safe, a, 0); %#ok<ASGLU>
                
                % We need to coregister the ramp again...
                resampledRamp = interp2(meshAz', meshRange', derampPhase',...
                        refMeshAz'+a',refMeshRange'+r','cubic',nan);
                    
                    
                productType = typeCell{1};
                
                if strcmpi(productType, 'VV') || strcmpi(productType, 'VH') || strcmpi(productType, 'HV') || strcmpi(productType, 'HH')
                    geoTiffObj.TYPE = productType;
                    % Load the raw data
                    data = engine.load( OI.Data.CoregisteredSegment().configure( ...
                        'STACK', num2str(this.STACK), ...
                        'VISIT_INDEX', num2str(this.VISIT), ...
                        'POLARIZATION', productType, ...
                        'REFERENCE_SEGMENT_INDEX', num2str(this.SEGMENT) ) ...
                    )';
                    if isempty(data)
                        return
                    end
                    data = data.*exp(1i.*resampledRamp');
                    data = log(abs(data));
%                     data = avfilt(log(abs(data))');
                elseif strcmpi(productType, 'VV_COHERENCE') || strcmpi(productType, 'VH_COHERENCE')
                    geoTiffObj.TYPE = productType;
                    % Load the raw data
                    data1 = engine.load( OI.Data.CoregisteredSegment().configure( ...
                        'STACK', num2str(this.STACK), ...
                        'VISIT_INDEX', num2str(this.VISIT), ...
                        'POLARIZATION', productType(1:2), ...
                        'REFERENCE_SEGMENT_INDEX', num2str(this.SEGMENT) ) ...
                    )';
                    delta = 1;
                    if numel(thisStack.visits) == this.VISIT
                        delta = -1;
                    end
                    data2 = engine.load( OI.Data.CoregisteredSegment().configure( ...
                        'STACK', num2str(this.STACK), ...
                        'VISIT_INDEX', num2str(this.VISIT + delta), ...
                        'POLARIZATION', productType(1:2), ...
                        'REFERENCE_SEGMENT_INDEX', num2str(this.SEGMENT) ) ...
                    )';
                    if isempty(data1) || isempty(data2)
                        return
                    end
                    
                    data = abs(avfilt(data1.*conj(data2))./avfilt(sqrt(abs(data1).^2.*abs(data2).^2)));
                end

                betterSamples(:) = mapping.distance(:) < currentDistance(:);
                
                % check there is valid data here
                [sAz, sRg]=ind2sub(refSz,mapping.closestIndices);
                invalidData = any( ...
                    sAz < validSamples.firstAzimuthLine | ...
                    sAz > validSamples.lastAzimuthLine | ...
                    sRg < validSamples.firstRangeSample | ...
                    sRg > validSamples.lastRangeSample, 2);
                betterSamples(invalidData) = false;
                
                currentDistance(betterSamples) = mapping.distance(betterSamples);
                % interpolate the data
                output(betterSamples) = ...
                    sum(data(mapping.closestIndices(betterSamples,:)) ...
                    .* mapping.weights(betterSamples,:), 2);
                
            end
            % mask any baddies, here anything more than 15 meters from data
            output(currentDistance> 15 ) = nan;
            % save the output
            engine.save(geoTiffObj, output);

            filename = geoTiffObj.identify(engine).filepath;
            % save the GeoTiff
            geotiffwrite(filename, output, tiffMeta);
        end

        % mark this job as finished
        this.isFinished = true;
        
    end % run
    
    function mappingCells = load_mapping(this, engine, thisStack)
        % load the mapping data
        segments = thisStack.reference.segments.index;
        for segInd = numel(segments):-1:1
            segIndInStack = thisStack.reference.segments.index(segInd);
            % Load the mapping
            mapping = engine.load(OI.Data.GeoTiffMapping().configure( ...
                'STACK', this.STACK, ...
                'SEGMENT', segIndInStack ...
            ));
            mappingCells{segInd} = mapping;
        end
    end
    
    function this = queue_jobs(this, engine, stacks)
        
        
        % TODO this info should now be in STACKS object
        cat = engine.load(OI.Data.Catalogue() );

        jobCount = 0;
        mapAvailable = true( numel(stacks.stack), 1 );
        uselessStack = mapAvailable;
        for stackIndex = 1:numel(stacks.stack)
            thisStack = stacks.stack(stackIndex);
            for refSegInd = thisStack.reference.segments.index
                % Check if mapping is available,
                mappingObj = OI.Data.GeoTiffMapping().configure( ...
                    'STACK', num2str(stackIndex), ...
                    'SEGMENT', num2str(refSegInd)).identify(engine);
                if uselessStack(stackIndex)
                    mapResult = engine.load(mappingObj);
                else
                    mapResult = engine.database.find(mappingObj);
                end
                
                if isempty( mapResult )
                    mapAvailable(stackIndex) = false;
                    jobCount = jobCount + 1;
                    engine.requeue_job_at_index( ...
                        jobCount, ...
                        'SEGMENT', refSegInd, ...
                        'STACK', stackIndex);
                else % If we have mappings, check they cover the AOI
                    if uselessStack(stackIndex) && any(mapResult.distance < 50)
                       uselessStack(stackIndex) = false;
                    end
                end
            end
        end

        for stackIndex = 1:numel(stacks.stack)
            thisStack = stacks.stack(stackIndex);
            if ~mapAvailable(stackIndex) || uselessStack(stackIndex)
                continue
            end


            for visitIndex = 1:numel(thisStack.visits)
                firstSeg = find(thisStack.correspondence(:,visitIndex),1);
                if isempty(firstSeg)
                    engine.ui.log('debug','No valid data for this date, in this stack and segment\n');
                    continue
                end
                segmentInd = thisStack.correspondence(firstSeg,visitIndex);
                safeInd = thisStack.segments.safe(segmentInd);
                visitDatestr = cat.safes{safeInd}.date.datestr;

                resultObj = OI.Data.GeoTiff().configure( ...
                    'STACK', num2str(stackIndex), ...
                    'VISIT', num2str(visitIndex), ...
                    'TYPE', this.TYPE{1}, ...
                    'DATE', visitDatestr).identify(engine);

                if resultObj.exists
                    continue
                end

                jobCount = jobCount+1;
                engine.requeue_job_at_index( ...
                    jobCount, ...
                    'SEGMENT', refSegInd, ...
                    'VISIT', visitIndex, ...
                    'STACK', stackIndex, ...
                    'MAPPING_AVAILABLE', true);
                if jobCount > 200
                    break
                end
            end
        end
        
        if jobCount == 0
            this.isFinished = true;
            engine.save( this.outputs{1} )
        end
    end
    
    function this = generate_mapping(this, engine, stacks)
        % Generate the mapping
            % Load the geocoding coordinates
            geocodingObj = OI.Data.LatLonEleForImage().configure( ...
                'STACK', num2str(this.STACK), ...
                'SEGMENT_INDEX', num2str(this.SEGMENT) ).identify(engine);
            lle = engine.load(geocodingObj);
            if isempty(lle)
                return
            end
        
            % load stitching info to mark no-data
            stitch = engine.load ( OI.Data.StitchingInformation());
            if isempty(stitch)
                return
            end
            
            thisStitch = stitch.stack(this.STACK).segments(this.SEGMENT);
            validStitch = thisStitch.validSamples;
            
            % TODO we really need a better way of getting input size...
            % Get metadata for reference
            preprocessingInfo = engine.load( OI.Data.PreprocessedFiles() );
            refSafeIndex = stacks.stack(this.STACK).segments.safe( this.SEGMENT );
            refSwathIndex = stacks.stack(this.STACK).segments.swath( this.SEGMENT );
            refSwathInfo = ...
                preprocessingInfo.metadata(refSafeIndex).swath(refSwathIndex);
            [lpbRef,spbRef,~,~] = ...
                OI.Plugins.Geocoding.get_parameters( refSwathInfo );
            inputSize = [lpbRef,spbRef];
            blockLat = reshape(lle(:,1), inputSize(1), inputSize(2));
            blockLon = reshape(lle(:,2), inputSize(1), inputSize(2));
            
           % define the output grid
            oGrid = this.generate_grid(this.AOI, this.SIZE);
            latGrid = oGrid.latGrid;
            lonGrid = oGrid.lonGrid;

            % define the transformation between the az/rg and lat/lon coordinate systems
            % in this case we will use a linear weighting of the nearest 4 pixels
            % thus rather than requiring an [inputX*inputY x outputX*outputY] matrix, we just need a [outputX*outputY x 4] matrix
            % the 4 columns are the indices of the 4 nearest pixels in the input image
            % nPixels = prod(sz);

            % So the goal is to find, for each point in the output grid, a set of 4 nearby samples in the input grid
            % and four associated weights.
            % closestIndices = zeros(nPixels,4); 
            % weights = zeros(nPixels,4);

            % Find the indices of the 4 points for each square
            allInds = reshape(1:numel(blockLat), size(blockLat));
            squareIndices = zeros(numel(allInds(1:end-1,1:end-1)),4);
            
            squareIndices(:,1) = reshape(allInds(1:end-1,1:end-1),[],1); % Top left
            squareIndices(:,2) = reshape(allInds(1:end-1,2:end),[],1); % Top right
            squareIndices(:,3) = reshape(allInds(2:end,2:end),[],1); % Bottom right
            squareIndices(:,4) = reshape(allInds(2:end,1:end-1),[],1); % Bottom left
        
            % Find the average lat/lon of each square
            inputSquaresLat = (1/4).* ( ...
                blockLat(1:end-1,1:end-1) + ...
                blockLat(2:end,1:end-1) + ...
                blockLat(1:end-1,2:end) + ...
                blockLat(2:end,2:end) );
            inputSquaresLon = (1/4).* ( ...
                blockLon(1:end-1,1:end-1) + ...
                blockLon(2:end,1:end-1) + ...
                blockLon(1:end-1,2:end) + ...
                blockLon(2:end,2:end) );
            
            inputLat = inputSquaresLat;
            inputLon = inputSquaresLon;
            outputLat = oGrid.latGrid;
            outputLon = oGrid.lonGrid;
            % Calculate the average shift in latitude and longitude for each pixel shift
            avgLatPerShiftRight = mean(diff(inputLat(1, :)));
            avgLonPerShiftRight = mean(diff(inputLon(1, :)));
            avgLatPerShiftUp = mean(diff(inputLat(:, 1)));
            avgLonPerShiftUp = mean(diff(inputLon(:, 1)));

            % Initialize solution subscripts
            [solutionX, solutionY] = deal(ones(size(outputLat)));
            limitX = @(xSub) min(max(xSub, 1), size(inputLat,2));
            limitY = @(ySub) min(max(ySub, 1), size(inputLat,1));
            easy_sub2ind = @(sz, rows, cols) (cols - 1) * sz(1) + rows;

            iter = 0;
            while true
                % Calculate indices for the current solution
                solutionIndices = easy_sub2ind(size(inputLat), solutionY, solutionX);

                % Calculate errors in latitude and longitude
                latError = outputLat - inputLat(solutionIndices);
                lonError = outputLon - inputLon(solutionIndices);

                % Calculate the pixel shift for each error
                % lonShift = round(lonError / avgLonPerShiftRight);
                % latShift = round(latError / avgLatPerShiftUp);
                shiftYX = round( [latError(:), lonError(:)] / ...
                    [ ...
                    avgLatPerShiftUp, avgLonPerShiftUp; ...
                    avgLatPerShiftRight avgLonPerShiftRight ...
                    ]);

                if iter<10
                    % Calculate the new solution subscripts
                    solutionX(:) = solutionX(:) + shiftYX(:,2);
                    solutionY(:) = solutionY(:) + shiftYX(:,1);
                    solutionX = limitX(solutionX);
                    solutionY = limitY(solutionY);
                end
                
                
                % Recalculate indices and error
                solutionIndices = easy_sub2ind(size(inputLat), solutionY, solutionX);
                latError = outputLat - inputLat(solutionIndices);
                lonError = outputLon - inputLon(solutionIndices);

                % Check if the solution has converged
                % Shift one pixel in each direction, U D L R
                % If shifting in any direction increases the error, then the solution
                % has converged
                % Shift up
                upIndices = easy_sub2ind(size(inputLat), limitY(solutionY+1), solutionX);
                upErrorLat = outputLat - inputLat(upIndices);
                upErrorLon = outputLon - inputLon(upIndices);

                downIndices = easy_sub2ind(size(inputLat), limitY(solutionY-1), solutionX);
                downErrorLat = outputLat - inputLat(downIndices);
                downErrorLon = outputLon - inputLon(downIndices);

                leftIndices = easy_sub2ind(size(inputLat), solutionY, limitX(solutionX-1));
                leftErrorLat = outputLat - inputLat(leftIndices);
                leftErrorLon = outputLon - inputLon(leftIndices);

                rightIndices = easy_sub2ind(size(inputLat), solutionY, limitX(solutionX+1));
                rightErrorLat = outputLat - inputLat(rightIndices);
                rightErrorLon = outputLon - inputLon(rightIndices);

                % get masks for each direction in terms of if the error decreases
                err = latError.^2 + lonError.^2;
                % disp(sum(err(:)))
                uErr = upErrorLat.^2 + upErrorLon.^2;
                dErr = downErrorLat.^2 + downErrorLon.^2;
                lErr = leftErrorLat.^2 + leftErrorLon.^2;
                rErr = rightErrorLat.^2 + rightErrorLon.^2;
                
                upBetter = uErr < err;
                downBetter = dErr < err;
                leftBetter = lErr < err;
                rightBetter = rErr < err;

                anyBetter = upBetter | downBetter | leftBetter | rightBetter;
            
                upBetter( dErr < uErr ) = false;
                downBetter( uErr < dErr ) = false;
                leftBetter( rErr < lErr ) = false;
                rightBetter( lErr < rErr ) = false;

                if ~any(anyBetter(:)) || iter >= 100
                    break
                end
                
                engine.ui.log('info','%i pix remaining\n', sum(anyBetter(:)))

                udb = upBetter | downBetter;
                lrb = leftBetter | rightBetter;
                
                udb( min(lErr, rErr) < min(uErr, dErr) ) = false;
                lrb( min(uErr, dErr) < min(lErr, rErr) ) = false;
                
                % Update the solution subscripts
                solutionX(lrb) = limitX(solutionX(lrb) + rightBetter(lrb) - leftBetter(lrb));
                solutionY(udb) = limitY(solutionY(udb) + upBetter(udb) - downBetter(udb));
                
                iter = iter + 1;
            end

            % Get the indices of the 4 points in the closest square
            solutionIndices = easy_sub2ind(size(inputLat), solutionY, solutionX);
            closestIndices = squareIndices(solutionIndices(:),:);
        
            % Calculate the weights for the 4 nearest points
            d2 = zeros(size(closestIndices)); % distance squared
            lat2meters = (1/360) * 40008e3;
            lon2meters = cosd(mean(latGrid(:))) * (1/360) * 40075e3;
            for ii=4:-1:1
                d2(:,ii) = ( ...
                    ( blockLat(closestIndices(:,ii)) - latGrid(:) ) ...
                    * lat2meters ).^2 + ( ...
                    ( blockLon(closestIndices(:,ii)) - lonGrid(:) ) ...
                    * lon2meters ).^2;
            end
            weights = 1./sqrt(d2); % inverse distance weighting
            weights = weights./sum(weights,2); % normalise the weights

            % Store the results of the mapping
            mappingObj = OI.Data.GeoTiffMapping().configure( ...
                'STACK', this.STACK, ...
                'SEGMENT', this.SEGMENT ...
            );
            mappingObj.weights= weights;
            mappingObj.closestIndices = closestIndices;
            mappingObj.inputSize = inputSize;
            mappingObj.outputSize = this.SIZE;
            mappingObj.inputFile = geocodingObj.filepath;
            mappingObj.distance = sqrt(mean(d2,2));
            
            % Mark any invalid tiles as a very high distance to indicate
            % oor
            azTooLow = solutionY < validStitch.firstAzimuthLine;
            azTooHigh = solutionY > validStitch.lastAzimuthLine;
            rgTooLow = solutionX < validStitch.firstRangeSample;
            rgTooHigh = solutionX > validStitch.lastRangeSample;
            baddies = azTooLow | azTooHigh | rgTooLow | rgTooHigh;
            mappingObj.distance(baddies) = 9e9;
            
            % save the mapping
            engine.save( mappingObj );
            this.isFinished = true;
    end
end % methods


methods (Static = true)

    function geoTiffMetadata = get_geotiff_metadata( lat, lon, SIZE )
        R=georefcells();        
        R.LatitudeLimits = [min(lat(:)),max(lat(:))];
        R.LongitudeLimits = [min(lon(:)),max(lon(:))];
        R.RasterSize= SIZE;
        R.ColumnsStartFrom = 'south';
        R.RowsStartFrom = 'west';
        R.CellExtentInLatitude = lat(2)-lat(1);
        R.CellExtentInLongitude = lon(1,2) - lon(1,1);
        geoTiffMetadata = R;
    end % get_geotiff_info

    function grid = generate_grid( aoi, SIZE )
        % generate a grid of lat/lon coordinates
        % aoi is an AOI object or a [1x4] array defining the [North, East, South, West] limits of the output image in lat/lon.
        % size is a [1x2] array defining the number of pixels in the [lon, lat] axes respectively.
        
        if isa(aoi, 'OI.Data.AreaOfInterest')
            aoi = [aoi.northLimit aoi.eastLimit aoi.southLimit aoi.westLimit];
        elseif ~isnumeric(aoi) || numel(aoi) ~= 4
            error('AOI must be an AreaOfInterest object or a [1x4] array defining the [North, East, South, West] limits of the output image in lat/lon.')
        end

        % Define the grid
        grid = struct();
        grid.latAxis = linspace(aoi(3), aoi(1), SIZE(1));
        grid.lonAxis = linspace(aoi(4), aoi(2), SIZE(2));
        [grid.lonGrid, grid.latGrid] = meshgrid(grid.lonAxis, grid.latAxis);

    end % generate_grid
end % methods (Static = true)

end % classdef