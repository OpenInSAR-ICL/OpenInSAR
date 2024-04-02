classdef Coregistration < OI.Plugins.PluginBase
properties
    inputs = {OI.Data.Stacks(), OI.Data.PreprocessedFiles(), OI.Data.DEM()}
    outputs = {OI.Data.CoregistrationSummary()}
    id = 'Coregistration'
    referenceSegmentIndex 
    trackIndex
    visitIndex
end

methods
    function this = Coregistration( varargin )
        this.isArray = true;
    end

    function this = run( this, engine, varargin )
        
        engine.ui.log('debug','Begin loading inputs for %s\n',this.id);
        START_QUEUE_SIZE = engine.queue.length();
        
        cat = engine.load( OI.Data.Catalogue() );
        preprocessingInfo = engine.load( OI.Data.PreprocessedFiles() );
        stacks = engine.load( OI.Data.Stacks() );
        dem = engine.load( OI.Data.DEM() );
        projObj = engine.load( OI.Data.ProjectDefinition() );
        
        if isprop(projObj,'MAX_QUEUE_SIZE')
            MAX_QUEUE_SIZE = projObj.MAX_QUEUE_SIZE;
        else
            MAX_QUEUE_SIZE = 200; % default
        end

        if isempty(preprocessingInfo) || isempty(stacks) || isempty(dem) || isempty(cat)
            return;
        end
        
        engine.ui.log('debug','Finished loading for %s\n',this.id);
        if isempty(this.referenceSegmentIndex)
            % check if all the data is in the database
            allDone = true;
            jobCount = 0;
            for trackInd = 1:numel(stacks.stack)
                trackDone = true;
                dbDoneTrackObj = sprintf('done_coreg_track_%i',trackInd);
                if ~isempty(engine.database.fetch(dbDoneTrackObj))
                    continue
                end
                
            for refSegInd = stacks.stack(trackInd).reference.segments.index
                refSegDone = true;
                dbDoneSegObj = sprintf('done_coreg_track_%i_seg_%i',trackInd, refSegInd);
                if ~isempty(engine.database.fetch(dbDoneSegObj))
                    continue
                end
            for visitInd = ...
                1:numel(stacks.stack(trackInd).correspondence(refSegInd,:))
                
                % If there is no data for this combination of visit/segment
                % skip
                segmentIndexInStack = ...
                    stacks.stack(trackInd).correspondence(refSegInd, visitInd);
                if segmentIndexInStack == 0 % no data for this combo
                    continue
                end
                safeIndex = stacks.stack(trackInd).segments.safe(segmentIndexInStack);
                polFromSafe = cat.safes{safeIndex}.polarization;
                polCells = cellstr(reshape(polFromSafe, 2, [])')';
                nPols = numel(polCells);
                results = cell(1+nPols,1);
                results{1} = OI.Data.CoregOffsets().configure( ...
                    'STACK', num2str(trackInd), ...
                    'REFERENCE_SEGMENT_INDEX', num2str(refSegInd), ...
                    'VISIT_INDEX', num2str(visitInd), ...
                    'SEGMENT_INDEX', num2str(segmentIndexInStack) );
                iPol = 1;
                for polCell = polCells
                    results{1+iPol} = OI.Data.CoregisteredSegment().configure( ...
                        'STACK', num2str(trackInd), ...
                        'REFERENCE_SEGMENT_INDEX', num2str(refSegInd), ...
                        'VISIT_INDEX', num2str(visitInd), ...
                        'SEGMENT_INDEX', num2str(segmentIndexInStack), ...
                        'POLARIZATION', polCell{1});
                    iPol = iPol+1;
                end
                thisOneMissing = false;
                for ii=1:numel(results)
                    results{ii} = results{ii}.identify( engine );
                    resultInDatabase = engine.database.find( results{ii} );
                    if isempty(resultInDatabase)
                        thisOneMissing = true;
                    end
                end
                % latch off - were not done
                allDone = allDone && ~thisOneMissing; 
                if allDone % add to output
                    this.outputs{1}.value(end+1,:) = [trackInd, refSegInd, visitInd];
                elseif thisOneMissing
                    trackDone = false;
                    refSegDone = false;
                    jobCount = jobCount+1;
                    engine.requeue_job_at_index( ...
                        jobCount, ...
                        'trackIndex',trackInd, ...
                        'referenceSegmentIndex', refSegInd, ...
                        'visitIndex', visitInd);
                    
                    if engine.queue.length - START_QUEUE_SIZE > MAX_QUEUE_SIZE
                        return % We have enough jobs, we're wasting time!
                    end
                end
            end % visit
            if refSegDone
                engine.database.add(1,dbDoneSegObj);
            end
            end % reference
            if trackDone
                engine.database.add(1,dbDoneTrackObj);
            end
            end % track
            if allDone % we have done all the tracks and segments
                engine.save( this.outputs{1} );
                this.isFinished = true;
            end
            return;
        end

        % Get the expected results:
        refSegInd = this.referenceSegmentIndex;
        stackInd = this.trackIndex;
        segInd = stacks.stack(stackInd).correspondence(refSegInd, this.visitIndex);
        
        result = OI.Data.CoregOffsets().configure( ...
            'STACK', num2str(this.trackIndex), ...
            'REFERENCE_SEGMENT_INDEX', num2str(this.referenceSegmentIndex), ...
            'VISIT_INDEX', num2str(this.visitIndex), ...
            'SEGMENT_INDEX', num2str( segInd ), ...
            'overwrite', this.isOverwriting ).identify( engine );
        resultsExist = true;
        resultFromDatabase = engine.database.find( result );
        haveFoundOffsets = ~isempty( resultFromDatabase );
        if ~haveFoundOffsets || this.isOverwriting
            resultsExist = false;
        end
        while resultsExist

            % also coregistered data
            result2 = OI.Data.CoregisteredSegment().copy_parameters( result );
            % get the safe index
            safeIndex = stacks.stack(stackInd).segments.safe( segInd );
            % get the safe
            safe = cat.safes{safeIndex};

            % check if we have HH, VV, VH
            [hasHH, hasVV, hasVH] = deal(false);
            % of various polarizations
            if strfind(projObj.POLARIZATION,'HH') & ...
                    strfind(safe.polarization,'HH')
                hasHH = true;
                resultHH = result2;
                resultHH.POLARIZATION = 'HH';
                % TODO by the time this is implemented the syntax will have
                % changed
                if isempty( engine.database.find( resultHH ) )
                    resultsExist = false;
                    break
                end
            end
            if strfind(projObj.POLARIZATION,'VV') & ...
                    strfind(safe.polarization,'VV') %#ok<*AND2>
                hasVV = true;
                resultVV = result2;
                resultVV.STACK = num2str(this.trackIndex);
                resultVV.REFERENCE_SEGMENT_INDEX = num2str(this.referenceSegmentIndex);
                resultVV.VISIT_INDEX = num2str(this.visitIndex);
                resultVV.POLARIZATION = 'VV';
                resultVV = resultVV.identify( engine );
                if isempty( engine.database.find( resultVV ) )
                    resultsExist = false;
                    break
                end
            end
            if strfind(projObj.POLARIZATION,'VH') & ...
                    strfind(safe.polarization,'VH')
                hasVH = true;
                resultVH = result2;
                resultVH.STACK = num2str(this.trackIndex);
                resultVH.REFERENCE_SEGMENT_INDEX = num2str(this.referenceSegmentIndex);
                resultVH.VISIT_INDEX = num2str(this.visitIndex);
                resultVH.POLARIZATION = 'VH';
                resultVH = resultVH.identify( engine );
                if isempty( engine.database.find( resultVH ) )
                    resultsExist = false;
                    break
                end
            end
            break;
        end

        engine.ui.log('info',...
            'Coregistration for track #%s, segment #%s, visit #%s\n',...
            result.STACK, result.REFERENCE_SEGMENT_INDEX, result.VISIT_INDEX)
        % check if output exists already
        if ~this.isOverwriting && ...
           resultsExist
            % add it to database so we know later
            engine.database.add( result );
            if hasHH
                result2.POLARIZATION = 'HH';
                engine.database.add( resultHH );
            end
            if hasVV
                engine.database.add( resultVV );
            end
            if hasVH
                result2.POLARIZATION = 'VH';
                engine.database.add( resultVH );
            end
            % go back to the engine to get the next job
            this.isFinished = true;
            return;
        end

        
        assert(segInd ~= 0,...
            ['Requested data segment does not appear to exist.' ...
            'This job should have been skipped.'])

        % address of the data in the catalogue and metadata
        safeIndex = stacks.stack(stackInd).segments.safe( segInd );
        swathIndex = stacks.stack(stackInd).segments.swath( segInd );
        burstIndex = stacks.stack(stackInd).segments.burst( segInd );
        swathInfo = ...
            preprocessingInfo.metadata( safeIndex ).swath( swathIndex );
    
        % Get metadata for reference
        refSafeIndex = stacks.stack(stackInd).segments.safe( refSegInd );
        refSwathIndex = stacks.stack(stackInd).segments.swath( refSegInd );
        refBurstIndex = stacks.stack(stackInd).segments.burst( refSegInd );
        refSwathInfo = ...
            preprocessingInfo.metadata(refSafeIndex).swath(refSwathIndex);

        % Size of reference data array
        [lpbRef,spbRef,~,~] = ...
            OI.Plugins.Geocoding.get_parameters( refSwathInfo );
        [refMeshRange, refMeshAz] = ...
            OI.Plugins.Geocoding.get_geometry(lpbRef,spbRef);
        refSz = [lpbRef, spbRef];

        % get parameters from metadata
        [lpb,spb,nearRange,rangeSampleDistance] = ...
            OI.Plugins.Geocoding.get_parameters( swathInfo );

        [meshRange, meshAz] = ...
            OI.Plugins.Geocoding.get_geometry(lpb,spb);
        ati = swathInfo.azimuthTimeInterval;
        c = 299792458;
        lambda = c/swathInfo.radarFrequency;
        
        % orbits for coreg and deramping
        [orbit, lineTimes] = ...
            OI.Plugins.Geocoding.get_poe_and_timings( ...
                cat, safeIndex, swathInfo, burstIndex );
        origLineTimes = lineTimes;
        
        % Orbit for the reference
        [refOrbit, refLineTimes] = ...
            OI.Plugins.Geocoding.get_poe_and_timings( ...
                cat, refSafeIndex, refSwathInfo, refBurstIndex ); %#ok<ASGLU>

        % ensure 'virtual' timings for secondary match the size of reference timings
        if (lpbRef ~= lpb)
            engine.ui.log('warning',...
                ['Lines per burst mismatch between reference and secondary' ...
                'during coregistration of visit %i segment %i\n'], ...
                this.visitIndex, this.referenceSegmentIndex)
            isLongOnFirstDim = size(lineTimes,1) > size(lineTimes,2);
            lineTimes=lineTimes(1):ati/86400:(lineTimes(1)+(lpbRef-1)*ati/86400);
            if isLongOnFirstDim
                lineTimes = lineTimes(:);
            end
        end
        % ...   The output raster has to match the dims of the reference.
        %       We will find the indices which satisfy this, even if they're out of
        %       the segment.     
  

        % If we use large values for t, we reach the limits of double
        % precision, causing horrendous bugs and phase shifts
        % orbitCentre = mean(orbit.t);
        orbitCentre = mean(lineTimes);
        origLineTimes = origLineTimes - orbitCentre;
        lineTimes = lineTimes - orbitCentre;
        orbit.t = orbit.t - orbitCentre;

        if ~haveFoundOffsets % if we already have offsets we can skip this
            % we need one more input...
            geocodingData = OI.Data.LatLonEleForImage().configure( ...
                'STACK', num2str(this.trackIndex), ...
                'SEGMENT_INDEX', num2str(this.referenceSegmentIndex) ...
            ).identify(engine);
            lle = engine.load( geocodingData );
            if isempty(lle)
                engine.ui.log('info',...
                    'No geocoding data for track #%s, segment #%s, visit #%s\n',...
                    result.STACK, result.REFERENCE_SEGMENT_INDEX, result.VISIT_INDEX)
                return % throw back to engine to generate geocoding data
            end

            % We start with a single line:

            tOrbit = orbit.interpolate( lineTimes );
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
    
            % Estimate the doppler rate
            refGroundXYZ = OI.Functions.lla2xyz( lle );
            midDem = OI.Functions.lla2xyz(mean(lle)); 
            % mean xyz would be ...
            % below the surface of the earth, as compared to mean lle.
            linesPerDoppler =  lpbRef./ ...
                ( OI.Functions.doppler_eq(satXYZ(1,:), satV(1,:), midDem) - ...
                OI.Functions.doppler_eq(satXYZ(end,:), satV(end,:), midDem) );
    
            % Find the doppler error and use this to align the azimuth lines
            satT = lineTimes;
            lastErr = 9e9; iters =0; isConverged = false; iterLimit = 100;
            while ~isConverged
                [satT, dopplerErr] = ....
                    OI.Plugins.Coregistration.dopplerIter(...
                    satT, orbit, refGroundXYZ(1:spbRef:end,:), linesPerDoppler, ati);
                notMuchBetter = (sum(dopplerErr.^2) > lastErr * 0.99);
                notMuchWorse = (sum(dopplerErr.^2) < lastErr * 1.01);
                isConverged =  (notMuchBetter && notMuchWorse) || iters >= iterLimit;
                iters = iters + 1;
                lastErr = sum(dopplerErr.^2);
            end
            
            % repeat this but for the whole reference segment
            satT = repelem(satT,spbRef,1);
            lastErr = 9e9; iters =0; isConverged = false; iterLimit = 100;
            while ~isConverged
                [satT, dopplerErr] = ...
                    OI.Plugins.Coregistration.dopplerIter(...
                    satT, orbit, refGroundXYZ, linesPerDoppler, ati);
                isConverged = mean(abs(dopplerErr(:))) / lastErr > 0.99 || iters >= iterLimit;
                lastErr = mean(abs(dopplerErr(:)));
            end
           
            % calc azimuth azimuth shift
            a = (reshape(satT,refSz)-lineTimes)*86400./ati;
    
            % correct the ephemerides according to the new azimuth shift
            tOrbit = orbit.interpolate( satT );
            satXYZ = [ ...
                    tOrbit.x(:), ...
                    tOrbit.y(:), ...
                    tOrbit.z(:) ...
                ];
            
            % calculate the range offsets
            r = (OI.Functions.range_eq(satXYZ, refGroundXYZ) - nearRange) ./ ...
                swathInfo.rgSpacing - refMeshRange(:);
            % TODO I THINK THERE IS AS OFF BY ONE ERROR HERE. r should
            % equal r+1;
            r = reshape(r,refSz);
           
            % We can now clear the ground coordinates as we're just
            % resampling now.
            refGroundXYZ = [];
            dopplerErr = [];
            tOrbit = [];
            
            % save the results
            engine.save(result, [a(:) r(:)]);
        else
            azRgOffsets = engine.load( result );
            if isempty(azRgOffsets)
                return
            end
            a = reshape(azRgOffsets(:,1),refSz);
            r = reshape(azRgOffsets(:,2),refSz);
            clearvars azRgOffsets
        end

        % TODO
        % mask outside AOI
        % mask sea
        % don't save these areas
        % aoi = projObj.aoi.to_area();
        % [aoiLimS aoiLimN aoiLimW aoiLimE] = aoi.limits;
        % aoiMask = lat < aoiLimS | lat > aoiLimN | lon < aoiLimW | lon > aoiLimE;
        % sea = avfilt(reshape(lle(:,3),refSz),100,100)==0;
        % outOfBoundsMask = OI.Data.SubsetMask( ~sea & ~aoiMask );

        % resample the segment
        safe = cat.safes{safeIndex};
        refSafe = cat.safes{refSafeIndex};
        % for each polarisation requested and available
        for pol = {'HH','VH','VV'} % do default last, to align how we check
            % if the plugin has finished
            if isempty(strfind(projObj.POLARIZATION,pol{1}))
                continue % pol not requested
            end
            if isempty(strfind(safe.polarization,pol{1}))
                continue % no data for requested pol
            end
            coregSegmentInfo = OI.Data.CoregisteredSegment().configure( ...
                'POLARIZATION', pol{1}, ...
                'STACK', num2str(this.trackIndex), ...
                'SEGMENT_INDEX', num2str(segInd), ...
                'REFERENCE_SEGMENT_INDEX', num2str(this.referenceSegmentIndex), ...
                'VISIT_INDEX', num2str(this.visitIndex), ...
                'overwrite', this.isOverwriting ...
            );

            % load the reference data
            segPath = safe.get_tiff_path(swathIndex,pol{1});
            refSegPath = refSafe.get_tiff_path(refSwathIndex,pol{1}); %#ok<NASGU>

            % loady
            data = OI.Data.Tiff.read_cropped(...
                segPath, 1, [1 lpb]+(burstIndex-1)*lpb, []);
            
            % get ramp
            [derampPhase, ~, azMisregistrationPhase] = OI.Functions.deramp_demod_sentinel1(...
                swathInfo, burstIndex, orbit, safe, a, 0);
%             [derampPhase, demodulatePhase, azMisregistrationPhase] = OI.Functions.deramp_demod_sentinel1(...
%                 swathInfo, burstIndex, orbit, safe, a); %#ok<ASGLU>

            % resample
            coregData=interp2(meshAz', ...
                meshRange', ...
                double(data).*exp(1i.*derampPhase'), ...
                refMeshAz'+a', ...
                refMeshRange'+r', ...
                'cubic', ...
                nan);
            resampledRamp = interp2(meshAz', meshRange', derampPhase',...
                        refMeshAz'+a',refMeshRange'+r','cubic',nan);
            resampledAzPhase = interp2(meshAz', meshRange', azMisregistrationPhase',...
                refMeshAz'+a',refMeshRange'+r','cubic',nan);
            % resampledModulationPhase = interp2(meshAz', meshRange', ...
            %     demodulatePhase', refMeshAz'+a', refMeshRange'+r', ...
            %     'cubic', nan);

            % % Load the reference data
            % refData = OI.Data.Tiff.read_cropped( ...
            %     refSegPath, 1, [1 lpbRef]+(refBurstIndex-1)*lpbRef, []);
    
            % reramp, range compensate, adjust for misregistration
            coregData = coregData .* exp(-1i.*resampledRamp) .* ...
                exp( 1i * rangeSampleDistance * r' * 4 * pi / lambda) .* ...
                exp( -1i * resampledAzPhase );
    
            engine.save(coregSegmentInfo, coregData);
        end
        % we win
        this.isFinished = true;
    end % run
% normz = @(x) x./abs(x);
% avfilt = @(x,w,h) imfilter(x, fspecial('average', [w, h]));
% rdata = OI.Data.Tiff.read_cropped( cat.safes{ refSafeIndex }.strips{refSwathIndex }.getFilepath(),1,[1 lpb]+(stacks.stack(stackInd).segments.burst( refSegInd )-1)*lpb,[]);figure(2);
% rdata = double(rdata);
% p = coregData;
% s = rdata;
% p = normz(p);
% p(isnan(p))=0;
% s = normz(s);
% s(isnan(s))=0;
% ifg = (avfilt(p.*conj(s),100,20)');
% ifgRgb = (ind2rgb(round(254*OI.Functions.normalise_image(angle(ifg)))+1,jet));
% Brightness = 2.*OI.Functions.normalise_image(min(7,max(4,log(abs(rdata)+abs(coregData)))))';
% ifgRgbA = ifgRgb.*Brightness;
% imagesc(ifgRgbA)
end % methods

methods (Static = true)
    function [satT, dopplerErr] = dopplerIter(satT, orbit, demXYZ, ...
    linesPerDoppler, ati)
    
    % get ephemerides
    tOrbit = orbit.interpolate( satT );
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
    % get err
    dopplerErr = OI.Functions.doppler_eq(satXYZ, satV, demXYZ);

    % update time
    satT = satT + ( dopplerErr * ...
        linesPerDoppler * ...
        ati / (60*60*24) ) ;
    end
end

end % classdef
% 
% 'R:\projects\insardatastore\ephemeral\saa116\Wales\work\coregistration\CoregisteredSegment_stack_1_segment_6_visit_5_polarization_VH.mat'
% dd = dir('R:\projects\insardatastore\ephemeral\saa116\Wales\work\coregistration\');
% names = {dd.name};
% sizes = [dd.bytes];
% isData = cellfun( @(x) contains(x,'CoregisteredSegment_'), names);
% dataNames = names(isData);
% dataSizes = sizes(isData);
% 
% for ii=1:numel(dataNames)
%     name = dataNames{ii};
%     otherPol = 'VV';
%     myPol = 'VH';
%     mySize = dataSizes(ii);
%     if all(name(end-5:end-4) == otherPol)
%         otherPol = 'VH';
%         myPol = 'VV';
%     end
%     otherName = strrep(name, myPol, otherPol);
%     otherInd = find(strcmpi(dataNames,otherName));
%     if isempty(otherInd)
%         fprintf(1,'No other pol for %s', name);
%         continue
%     else
%         % due to compression.. diff file sizes...
%         if abs(mySize - dataSizes(otherInd)) > 100e6
%             warning('Mismatch for %s and %s - \n%i and %i\n',name, otherName, mySize, dataSize(otherInd))
%         end
%     end
% end
% 



