classdef Geocoding < OI.Plugins.PluginBase

properties
    inputs = {OI.Data.Stacks(), OI.Data.PreprocessedFiles(), OI.Data.DEM()}
    outputs = {OI.Data.GeocodingSummary()}
    id = 'Geocoding'
    segmentIndex 
    trackIndex
end

methods
    
function this = Geocoding( varargin )
    this.isArray = true;
end

function this = run( this, engine, varargin )
    TOLERANCE_IMPROVEMENT_SERIES = 10.^(0:-1:-2);
    engine.ui.log('info','Begin loading inputs for %s\n',this.id);

    % load inputs
    cat = engine.load( OI.Data.Catalogue() );
    preprocessingInfo = engine.load( OI.Data.PreprocessedFiles() );
    stacks = engine.load( OI.Data.Stacks() );
    dem = engine.load( OI.Data.DEM() );

    % If missing inputs, return and allow engine to requeue
    if isempty(preprocessingInfo) || isempty(stacks) || isempty(dem) || isempty(cat)
        return;
    end

    engine.ui.log('debug','Finished loading for %s\n',this.id);
    if isempty(this.segmentIndex)
        this = this.queue_jobs(engine, stacks);
        return;
    end

    % Check we're not done already
    segInd = this.segmentIndex;
    result = OI.Data.LatLonEleForImage();
    result.STACK = num2str(this.trackIndex);
    result.SEGMENT_INDEX = num2str(this.segmentIndex);
    result = result.identify( engine );
    result.overwrite = this.isOverwriting;

    if ~this.isOverwriting && ...
            exist([result.filepath '.' result.fileextension],'file')
        % add it to database so we know later
        engine.database.add( result );
        this.isFinished = true;
        return;
    end

    % address of the data in the catalogue and metadata
    safeIndex= stacks.stack(this.trackIndex).segments.safe( segInd );
    swathIndex =stacks.stack(this.trackIndex).segments.swath( segInd );
    burstIndex = stacks.stack(this.trackIndex).segments.burst( segInd );
    swathInfo = ...
        preprocessingInfo.metadata( safeIndex ).swath( swathIndex );

    % get parameters from metadata
    [lpb,spb,~,~] = ...
        OI.Plugins.Geocoding.get_parameters( swathInfo ); %#ok<ASGLU>

    % get the orbit
    engine.ui.log('info','Interpolating orbits\n');
    [orbit, lineTimes] = ...
        OI.Plugins.Geocoding.get_poe_and_timings( ...
            cat, safeIndex, swathInfo, burstIndex );  

    if isempty(orbit.t) % No orbit file
       return
    end
    
    tOrbit = orbit.interpolate( repmat(lineTimes,spb,1) );
    satXYZ = [ ...
            tOrbit.x(:), ...
            tOrbit.y(:), ...
            tOrbit.z(:) ...
        ];
    satV = [ ...
            tOrbit.vx(:), ...
            tOrbit.vy(:), ...
            tOrbit.vz(:) ...
        ];
    tOrbit = []; % clear mem

    % define this variable because matlab pollutes the namespace...
    elevation = 'a variable not a function'; %#ok<NASGU>


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %   GEOCODING
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    % ALIASES TO UPDATE XYZ COORDINATES AND ELEVATION
    xyzUpd = @OI.Functions.lla2xyz;

    % INITIAL ESTIMATES OF LAT LON ELE
    [lat, lon] = OI.Plugins.Geocoding.get_initial_geocoding( ...
        swathInfo, burstIndex);
    [dem, elevation] = dem.interpolate( lat, lon );
    xyz = xyzUpd( lat, lon, elevation );

    % RANGE DOPPLER ERROR ESTIMATES IN TERMS OF AZ/RG INDEX OFFSET
    % AZ ERROR VIA DOPPLER
    dopplerPerAzLine = OI.Plugins.Geocoding.get_doppler_per_line( ...
            swathInfo, satXYZ, satV, lat, lon, elevation);
    azUpd = @( xyz ) ...
    OI.Functions.doppler_eq( ...
        satXYZ, ...
        satV, ...
        xyz ) ...
        ./ dopplerPerAzLine;
    % RG ERROR
    [lpb,spb,nearRange,rangeSampleDistance] = ...
        OI.Plugins.Geocoding.get_parameters(swathInfo);
        sz=[lpb,spb];
    [rangeSample, azLine] = ...
        OI.Plugins.Geocoding.get_geometry(lpb,spb);
    rgUpd = @(xyz) rangeSample(:) - ...
        (OI.Functions.range_eq( satXYZ, xyz ) ...
        - nearRange ) ...
        ./ rangeSampleDistance;
    rgUpdSubset = @(xyz,subset) rangeSample(subset) - ...
        (OI.Functions.range_eq( satXYZ(subset,:), xyz ) ...
        - nearRange ) ...
        ./ rangeSampleDistance;

    % polynomials for lat/lon
    rgCentreScale = @(idx) (idx)/spb - .5;
    azCentreScale = @(idx) (idx)/lpb - .5;

    latByAzRg = [azCentreScale(azLine(:)) rgCentreScale(rangeSample(:)) ...
        ones(numel(azLine),1) ] \ ...
        lat(:);
    lonByAzRg = [azCentreScale(azLine(:)) rgCentreScale(rangeSample(:)) ...
        ones(numel(azLine),1) ] \ ...
        lon(:);

    errorToLat = @(azErr,rgErr) ...
        [azCentreScale(azErr)+.5, rgCentreScale(rgErr)+.5 0.*rgErr] * latByAzRg;
    errorToLon = @(azErr,rgErr) ...
        [azCentreScale(azErr)+.5, rgCentreScale(rgErr)+.5 0.*rgErr] * lonByAzRg;

    % Progressively narrow the tolerance for error:
    if ~exist('TOLERANCE_IMPROVEMENT_SERIES','var')
        TOLERANCE_IMPROVEMENT_SERIES = 10.^(0:-1:-3);
    end

    for tolerance = TOLERANCE_IMPROVEMENT_SERIES
        engine.ui.log('debug','Geocoding to a tolerance of %f pixels\n',tolerance);

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %   LINES OF ZERO DOPPLER
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % fix the lat lon until there is zero doppler error

        doppIter = 0;
        dopStartTime = tic;
        % Eventually halve the shift to prevent bouncing
        dampingCurve = @(iter) 1/2+exp(-(iter-1).^3/500)/2;
        % Proper newton raphson would probably work better but this is fine.
        while doppIter < 10
            doppIter = doppIter + 1;
            azError = azUpd( xyz ) .* dampingCurve(doppIter);
            rgError = rgUpd( xyz );

            engine.ui.log('debug','Max doppler error is now: %f\n',max(abs(azError)));
            engine.ui.log('debug','Mean doppler error is now: %f\n',mean(abs(azError)));
            engine.ui.log('debug','Max rgError error is now: %f\n',max(abs(rgError)));
            engine.ui.log('debug','Mean rgError error is now: %f\n',mean(abs(rgError)));
            if max(abs(azError)) < tolerance
                engine.ui.log('debug','Doppler error is now within tolerance\n');
                break
            end

            % update lat/lon
            lat = lat + errorToLat(azError, rgError);
            lon = lon + errorToLon(azError, rgError);

            % TODO Go back and update DEM if it's not big enough
            % Limit to DEM extent for now
            lon = min(lon,max(dem.extent.lon(:)));
            lon = max(lon,min(dem.extent.lon(:)));
            lat = min(lat,max(dem.extent.lat(:)));
            lat = min(lat,max(dem.extent.lat(:)));

            [dem, elevation] = dem.interpolate( lat, lon );
            xyz = xyzUpd( lat, lon, elevation );

            % Errors here if outside dem extent!
            assert( sum(isnan(elevation)) == 0 ) 
        end % doppler loop
        engine.ui.log('info','Doppler loop took %f seconds\n',toc(dopStartTime));
        azError = []; rgError = []; % memory

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %   RANGE ZERO CROSSINGS
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % find the zero range error by triangulating the zero-crossing
        % update lat lon to their best life
        %             maybe update the error to lat lon ones too
%         lastLat = lat;
%         lastLon = lon;
        lastRgError = rgUpd( xyz );
        % the error functions need to be updated with the new zero doppler
        % polynomials
        latByAzRg = [azCentreScale(azLine(:)) rgCentreScale(rangeSample(:)) ...
            ones(numel(azLine),1) ] \ ...
            lat(:);
        lonByAzRg = [azCentreScale(azLine(:)) rgCentreScale(rangeSample(:)) ...
            ones(numel(azLine),1) ] \ ...
            lon(:);
        errorToLat = @(azErr,rgErr) ...
            [azCentreScale(azErr)+.5, rgCentreScale(rgErr)+.5 0.*rgErr] * latByAzRg;
        errorToLon = @(azErr,rgErr) ...
            [azCentreScale(azErr)+.5, rgCentreScale(rgErr)+.5 0.*rgErr] * lonByAzRg;

        initBoundsTime = tic;
        [errorWindow, hitCount] = deal(zeros(lpb*spb,2));

        %% NOW WE NEED TO FIND UPPER AND LOWER BOUNDS OF THE ZERO CROSSING bEFORE BISECTING %%
        % find the zero range error by triangulating the zero-crossing
        % A positive range error indicates that the range sample index 
        % being geocoded is at a range greater than the currently geocoded 
        % point (lat/lon). Generally, the lat/lon should be moved to a
        % greater range

        % progressively reduce range until we get a positive error
        lowRangeLat = lat;
        lowRangeLon = lon;
        highRangeLat = lat;
        highRangeLon = lon;
        lat = []; lon = []; % memory
        
        origRgError = lastRgError;
        tooFar = (lastRgError<0);
        fTF = find(tooFar);
        nTooFar = sum(tooFar);
        
        % only update samples that are past the bound
        while any(tooFar)
            const0 = zeros(nTooFar,1);
            const1 = const0 + 1;
            
            % shift and update
            lowRangeLat(fTF) = lowRangeLat(fTF) + ...
                errorToLat(const0, lastRgError(tooFar) - tolerance * const1);
            lowRangeLon(fTF) = lowRangeLon(fTF) + ...
                errorToLon(const0, lastRgError(tooFar) - tolerance * const1);
            [dem, elevation(fTF)] = ...
                dem.interpolate(lowRangeLat(fTF), lowRangeLon(fTF));
            xyz(fTF,:) = ...
                xyzUpd(lowRangeLat(fTF), lowRangeLon(fTF), elevation(fTF));
            
            % check error
            lastRgError(fTF,:) = rgUpdSubset(xyz(fTF,:), fTF);
            tooFar = (lastRgError<0);
            nTooFar = sum(tooFar);
            fTF = find(tooFar);
            engine.ui.log('debug','%i samples are too far.\n',nTooFar);
        end
        errorWindow(:,1) = lastRgError;

        % progressively increase range until we get a negative error
        lastRgError = origRgError;
        tooClose = (lastRgError>0);
        fTC = find(tooClose);
        nTooClose = sum(tooClose);
        while any(tooClose)
            const0 = zeros(nTooClose,1);
            const1 = const0 + 1;
            
            % shift and update
            highRangeLat(fTC) = highRangeLat(fTC) + ...
                errorToLat(const0, lastRgError(fTC) + tolerance * const1);
            highRangeLon(fTC) = highRangeLon(fTC) + ...
                errorToLon(const0, lastRgError(fTC) + tolerance * const1);
            [dem, elevation(fTC)] = ...
                dem.interpolate(highRangeLat(fTC), highRangeLon(fTC));
            xyz(fTC,:) = ...
                xyzUpd(highRangeLat(fTC), highRangeLon(fTC), elevation(fTC));
            
            % check error
            lastRgError(fTC,:) = rgUpdSubset(xyz(fTC,:), fTC);
            tooClose = (lastRgError>0);
            nTooClose = sum(tooClose);
            fTC = find(tooClose);
            engine.ui.log('debug','%i samples are too close.\n', nTooClose);
        end
        errorWindow(:,2) = lastRgError;

        engine.ui.log('info','Initialising bounds took %f seconds\n',toc(initBoundsTime));

        % Now we bisect to find the zero cross to a given tolerance
        hitCount = hitCount + 1; % we've now set each bound once.
        bisectZeroCrossingTime = tic;
        isOkay = zeros(lpb*spb,1,'logical');
        rzcIter = 1;
        
        % range zero crossing bisection iterations
        RZC_ITER_LIMIT = 10;
        while rzcIter < RZC_ITER_LIMIT
            rzcIter = rzcIter + 1;

            proportionalShift = errorWindow(:,1) ./ ...
                        (errorWindow(:,1) - errorWindow(:,2));
            % avoid divide by zero errors
            div0 = (errorWindow(:,1) - errorWindow(:,2)) == 0;
            proportionalShift(div0) = 0.5;

            % sometimes one bound will be really close and the other really far
            % away. This causes a lot of repetition. 
            % To fix this, bias it towards the underused bound.
            hitProportion = proportionalShift;
            hitProportion(~isOkay,:) = ...
                hitCount(~isOkay,1) ...
                ./(hitCount(~isOkay,1)+hitCount(~isOkay,2));
            proportionalShift = (hitProportion + proportionalShift)/2;
            
            % update lat/lon
            testLat = lowRangeLat + ...
                (highRangeLat - lowRangeLat) .* proportionalShift;
            testLon = lowRangeLon + ...
                (highRangeLon - lowRangeLon) .* proportionalShift;

            % update xyz and elevation
            [dem, elevation] = dem.interpolate( testLat, testLon );
            xyz = xyzUpd( testLat, testLon, elevation );

            % get the range error
            rgError = rgUpd( xyz );
            isPositiveError = rgError > 0;
            isNegativeError = rgError < 0;

            % update the error window, depending on the sign of the error
            errorWindow(isPositiveError,1) = rgError(isPositiveError);
            errorWindow(isNegativeError,2) = rgError(isNegativeError);

            % update the hit count
            hitCount(isPositiveError,1) = hitCount(isPositiveError,1) + 1;
            hitCount(isNegativeError,2) = hitCount(isNegativeError,2) + 1;

            % update the lat/lon
            lowRangeLat(isPositiveError) = testLat(isPositiveError);
            lowRangeLon(isPositiveError) = testLon(isPositiveError);
            highRangeLat(isNegativeError) = testLat(isNegativeError);
            highRangeLon(isNegativeError) = testLon(isNegativeError);

            % check for convergence
            isOkay = abs(rgError) < tolerance;
            engine.ui.log('debug', ...
                'Found zero crossings to tolerance for %.2f %% of pixels\n', ...
                100*sum(isOkay)./(spb*lpb));
            engine.ui.log('debug','Mean range error: %.3f\n',mean(abs(rgError)));

            % Set the geocoding to the best result so far.
            if all(isOkay) || rzcIter == RZC_ITER_LIMIT
                engine.ui.log('debug','Range error is now within tolerance\n');
                % choose the lowest error
                lowerBoundIsLowerError = ...
                    abs(errorWindow(:,1)) < abs(errorWindow(:,2));
                % Update lat/lon
                lat = highRangeLat;
                lon = highRangeLon;
                lat(lowerBoundIsLowerError) = ... 
                    lowRangeLat(lowerBoundIsLowerError);
                lon(lowerBoundIsLowerError) = ...
                    lowRangeLon(lowerBoundIsLowerError);
                % update ele
                [dem, elevation] = dem.interpolate( lat, lon );
                xyz = xyzUpd( lat, lon, elevation );
                break % we're done here
            end % check for converge
        end % while

        engine.ui.log('info','Triangulating zero crossing took %f seconds\n', ...
            toc(bisectZeroCrossingTime));

    end % MAIN TOLERANCE LOOP

    % save the result
    engine.save(result, [lat(:) lon(:) elevation(:)]);
    this.isFinished=true; % if we crash and burn now it doesn't matter
    
    % save a preview kml
    projObj = engine.load( OI.Data.ProjectDefinition() );
    previewDir = fullfile(projObj.WORK,'preview','geocoding');
    previewKmlPath = fullfile( previewDir, [result.id '.kml']);
    previewKmlPath = OI.Functions.abspath(previewKmlPath);
    OI.Functions.mkdirs( previewKmlPath );

    % make elevation image
    eleImage = reshape(elevation, sz);
    % scale to 0...1
    eleImage = OI.Functions.normalise_image(eleImage);
    % make a bit smaller
    eleImageRescaleFactor = 1000/max(sz);
    eleImage = imresize( eleImage, eleImageRescaleFactor );

    % get burst corners
    [~, ~, ~, ~, ~, cornerInds] = ...
        OI.Plugins.Geocoding.get_geometry(lpb,spb);
    previewImageArea = OI.Data.GeographicArea();
    previewImageArea.lat = lat(cornerInds);
    previewImageArea.lon = lon(cornerInds);
    previewImageArea.save_kml_with_image( ...
        previewKmlPath, ...
        flipud(eleImage) ); 

end % run

function this = queue_jobs(this, engine, stacks)
    % check if all the data is in the database
    allDone = true;
    jobCount = 0;
    for trackInd = 1:numel(stacks.stack)
        if isempty( stacks.stack( trackInd ).reference )
            continue;
        end
        for segmentInd = stacks.stack( trackInd ).reference.segments.index

            result = OI.Data.LatLonEleForImage();
            result.STACK = num2str(trackInd);
            result.SEGMENT_INDEX = num2str(segmentInd);
            result = result.identify( engine );
            resultInDatabase = engine.database.find( result );

            allDone = allDone && ~isempty( resultInDatabase );
            if allDone % add to output
                this.outputs{1}.value(end+1,:) = [trackInd, segmentInd];
            elseif isempty( resultInDatabase )
                jobCount = jobCount + 1;
                engine.requeue_job_at_index( ...
                    jobCount, ...
                    'trackIndex',trackInd, ...
                    'segmentIndex', segmentInd);
            end
        end %
    end %
    if allDone % we have done all the tracks and segments
        engine.save( this.outputs{1} );
        this.isFinished = true;
    end
end

end

methods (Static = true)
    function [lpb,spb,nearRange,rangeSampleDistance] = ...
            get_parameters(swathInfo)

        c = 299792458;
        nearRange = swathInfo.slantRangeTime * c / 2;

        % get image dimensions
        lpb = swathInfo.linesPerBurst;
        spb = swathInfo.samplesPerBurst;
        rangeSampleTime = 1/swathInfo.rangeSamplingRate;
        rangeSampleDistance = c*rangeSampleTime/2;
    end % get burst parameters

    function [rangeSample, azLine, burstCorners, sz, nSamps, cornerInds] = ...
            get_geometry(lpb,spb)
        % get meshgrid of range sample and az line 
        [rangeSample, azLine] = meshgrid( 1:spb, 1:lpb );
        sz=[lpb,spb];
        nSamps = prod(sz);
        % corners of the burst
        burstCorners = [ ...
            1, 1; ...
            1, spb; ...
            lpb, spb; ...
            lpb, 1 ...
        ];
        cornerInds = [1 (spb-1)*lpb+1 lpb*spb lpb]';
        % assert(all(rangeSample(cornerInds) == [1 spb spb 1]))
        % assert(all(azLine(cornerInds) == [1 1 lpb lpb]))
    end % get burst geometry

    function [orbit, lineTimes] = get_poe_and_timings( ...
            catalogue, safeIndex, swathInfo, burstIndex )
        
        % get the time of each line in the burst
        lineTimes = linspace( ...
            swathInfo.burst(burstIndex).startTime, ...
            swathInfo.burst(burstIndex).endTime, ...
            swathInfo.linesPerBurst )';

        % orbit file
        safe = catalogue.safes{safeIndex};
        orbit = OI.Data.Orbit( safe );
        
    end % get otbits and timings

    function [satXYZ, satV] = get_ephemerides( ...
            catalogue, safeIndex, swathInfo, burstIndex )

        [orbit, lineTimes] = ...
            OI.Plugins.Geocoding.get_poe_and_timings( ...
                catalogue, safeIndex, swathInfo, burstIndex );

        % interpolate the orbit
        burstOrbit = orbit.interpolate( lineTimes );
        satXYZ = [burstOrbit.x(:) burstOrbit.y(:) burstOrbit.z(:)];
        satV = [burstOrbit.vx(:) burstOrbit.vy(:) burstOrbit.vz(:)];

    end% get ephemerides

    function [lat, lon] = get_initial_geocoding( ...
            swathInfo, burstIndex)

        % get image dimensions
        lpb = swathInfo.linesPerBurst;
        spb = swathInfo.samplesPerBurst;

        % get geometry of the 
        [rangeSample, azLine, burstCorners, ~, nSamps] = ...
            OI.Plugins.Geocoding.get_geometry(lpb,spb);

        % get initial estimate of lat/lon
        % X = A\B is the solution to the equation A*X = B
        latLonPerAzRgConst = [burstCorners, ones(4,1)] \ ...
            [swathInfo.burst(burstIndex).lat(:), ...
            swathInfo.burst(burstIndex).lon(:)];

        lat = [azLine(:) rangeSample(:) ones(nSamps,1)] * ...
            latLonPerAzRgConst(:,1);
        lon = [azLine(:) rangeSample(:) ones(nSamps,1)] * ...
            latLonPerAzRgConst(:,2);
    end % get initial geocoding

    function dopplerPerAzLine = get_doppler_per_line( ...
            swathInfo, satXYZ, satV, lat, lon, ele)
        % get doppler rate over the burst
        midBurstXYZ = OI.Functions.lla2xyz( ...
            mean(lat(:)), ...
            mean(lon(:)),...
            mean(ele(:)));

        % get image dimensions
        lpb = swathInfo.linesPerBurst;
        spb = swathInfo.samplesPerBurst;

        % get geometry of the corners
        [~, ~, burstCorners, ~, ~] = ...
            OI.Plugins.Geocoding.get_geometry(lpb,spb);
        cornerInds = [1 (spb-1)*lpb+1 lpb*spb lpb];

        % cornerDoppler
        cornerDoppler = OI.Functions.doppler_eq( ...
                satXYZ(cornerInds,:), ...
                satV(cornerInds,:), ...
                midBurstXYZ);

        % regress to find doppler variation
        dopplerPerAzRgConst = [burstCorners ones(4,1)] \ cornerDoppler;
        dopplerPerAzLine = dopplerPerAzRgConst(1);
    end % doppler per az line

end % methods static

end % classdef
