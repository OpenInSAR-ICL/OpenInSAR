classdef BlockMap < OI.Data.DataObj
    properties
        id = 'BlockMap'
        generator = 'BlockMapping'
        stacks = struct()
    end

    methods
        function this = BlockMap()
            this.filepath = '$WORK$/$id$';
            this.fileextension = 'mat';
            this.hasFile = true;
        end

        function block = find_closest(this, lat, lon, stackInd)
            if nargin == 3
                stackInd = 1;
            end

            latDist = arrayfun(@(x) x.meanLat-lat, ...
                this.stacks(stackInd).blocks);
            lonDist = arrayfun(@(x) x.meanLon-lon, ...
                this.stacks(stackInd).blocks);
            dist = sqrt(latDist.^2+lonDist.^2);
            [~, closestInd] = min(dist);
            block = this.stacks(stackInd).blocks(closestInd);

        end

        function this = get_maps(this)
            for si = 1:numel(this.stacks)
                this = this.get_map_for_stack(si);
            end
        end

        function [minAz, maxAz, minRg, maxRg] = get_stack_limits(this, stackInd)
            minAz = inf;
            maxAz = -inf;
            minRg = inf;
            maxRg = -inf;

            stack = this.stacks(stackInd);
            for bi=1:numel(stack.blocks)
                block = stack.blocks(bi);
                minAz = min(minAz, block.azOutputStart);
                maxAz = max(maxAz, block.azOutputEnd);
                minRg = min(minRg, block.rgOutputStart);
                maxRg = max(maxRg, block.rgOutputEnd);
            end
        end

        function [size, azStart, azEnd, rgStart, rgEnd] = get_block_position(this, stackInd, blockInd, referenceFrame)

            % Default to output reference frame
            if nargin == 3
                referenceFrame = 'output';
            end

            whichReferenceFrame = find(strcmpi( ...
                referenceFrame, ...
                {'output','input'}));
                
            if isempty(whichReferenceFrame)
                warning('Unknown reference frame')
            end

            size = this.stacks(stackInd).blocks(blockInd).size;
            if whichReferenceFrame == 1
                azStart = this.stacks(stackInd).blocks(blockInd).azOutputStart;
                rgStart = this.stacks(stackInd).blocks(blockInd).rgOutputStart;
                azEnd = this.stacks(stackInd).blocks(blockInd).azOutputEnd;
                rgEnd = this.stacks(stackInd).blocks(blockInd).rgOutputEnd;
            elseif whichReferenceFrame == 2
                azStart = this.stacks(stackInd).blocks(blockInd).azDataStart;
                rgStart = this.stacks(stackInd).blocks(blockInd).rgDataStart;
                azEnd = this.stacks(stackInd).blocks(blockInd).azDataEnd;
                rgEnd = this.stacks(stackInd).blocks(blockInd).rgDataEnd;
            end

        end

        function [this, blockMapArray] = get_map_for_stack(this, stackInd)

            stack = this.stacks(stackInd);
            [~, maxAz, ~, maxRg] = this.get_stack_limits(stackInd);

            % Uint16 save memory. Likely to have more than 2^8, unlikely to have more than 2^16.
            blockMapArray=zeros(maxAz,maxRg,'uint16');

            for ii=1:numel(stack.blocks)
                block = stack.blocks(ii);
                blockMapArray( ...
                    block.azOutputStart:block.azOutputEnd, ...
                    block.rgOutputStart:block.rgOutputEnd) = ii;
            end
            this.stacks(stackInd).map = blockMapArray;
        end


        function kmlPath = make_map_kml(this, kmlDir)
            
            if nargin == 1
                kmlDir = '.';
            end
            
            if isempty(this.stacks) && isfield(this.stacks(1),'map')
                warning('Map not loaded')
            else

                for si = 1:numel(this.stacks)
                    stack = this.stacks(si);
                    if isempty(stack.map)
                        % Load the map
                        [~,stack.map] = this.get_map_for_stack(si);
                    end
                    % limit the size to avoid excessive memory usage
                    origSize = size(stack.map);
                    [maxDimV, maxDimI] = max(origSize);
                    if maxDimI > 1 % wide
                        outputSize = ...
                            [max(1024, round(4096*origSize(1)/maxDimV)), 4096];
                    else % tall
                        outputSize = ...
                            [4096, max(1024, round(4096*origSize(2)/maxDimV))];    
                    end
                    stack.map = imresize(stack.map,outputSize,'nearest');

                    
                    nBlocks = numel(stack.blocks);
                    map = OI.Functions.grayscale_to_rgb(stack.map,jet,[0 nBlocks]);
                    [blockLatCorners, blockLonCorners, blockAzCorners, blockRgCorners] = deal(zeros(nBlocks,4));

                    for bi=1:nBlocks
                        block = stack.blocks(bi);
                        % To determine the az/rg lat/lon extent of the map we will
                        % fit the az/rg coordinates against the lat/lon coordinates
                        % from the block corners.
                        blockLatCorners(bi,:) = block.latCorners(:)';
                        blockLonCorners(bi,:) = block.lonCorners(:)';
                        blockAzCorners(bi,:) = [block.azOutputStart block.azOutputEnd block.azOutputEnd block.azOutputStart];
                        blockRgCorners(bi,:) = [block.rgOutputStart block.rgOutputStart block.rgOutputEnd block.rgOutputEnd];
                    end

                    % Fit the az/rg coordinates against the lat/lon coordinates
                    % from the block corners.
                    nSamps = numel(blockLatCorners);
                    latCoeff = ...
                        [blockAzCorners(:),blockRgCorners(:) ones(nSamps,1)] \ ...
                        blockLatCorners(:);
                    lonCoeff =  ...
                        [blockAzCorners(:),blockRgCorners(:) ones(nSamps,1)] ...
                        \ blockLonCorners(:);

                    % Determine the lat/lon coordinates at the corners of the map
                    azRgCorners = [1 1; ...
                        1 origSize(2); ...
                        origSize(1) origSize(2); ...
                        origSize(1) 1];

                    mapLatCorners = [azRgCorners ones(4,1)] * latCoeff;
                    mapLonCorners = [azRgCorners ones(4,1)] * lonCoeff;


                    stackExtent = OI.Data.GeographicArea();
                    stackExtent.lat = mapLatCorners(:);
                    stackExtent.lon = mapLonCorners(:);
                    %stackExtent = stackExtent.make_counter_clockwise();

                    % Add some digits
                    borderPixels = 20;
                    for bi=1:nBlocks
                        block = stack.blocks(bi);
                        xMatch = find(sum(stack.map == bi));
                        yMatch = find(sum(stack.map == bi,2));
                        if numel(yMatch) < 60 || numel(xMatch) < 60
                            borderPixels = 1;
                        end
                        
                        bit = map(yMatch(1) + borderPixels: ...
                            yMatch(end) - borderPixels, ...
                            xMatch(1) + borderPixels: ...
                            xMatch(end) - borderPixels,...
                            :);
                        digit = imresize( ...
                            OI.Functions.digit_to_image( bi , true), ...
                            size(bit,[1 2]));

                        % We need to reorient the characters
                        % Depending on the orientation of the output kml,
                        % And due to ml/oct arrays being 'upside down' anyway.
                        isUpsideDown = stackExtent.lat(end)<stackExtent.lat(1);
                        if isUpsideDown
                            digit  = fliplr(digit);
                        else
                            digit = flipud(digit);
                        end
                        
                        % Highlight blocks in AOI
                        % block.blockInAOI & ~block.blockInSea
                        if block.usefulBlock 
                            % invert colour masking
                            digit = min(max(1-digit,0),1); 
                        end
                        
                        map(yMatch(1) + borderPixels: ...
                            yMatch(end) - borderPixels, ...
                            xMatch(1) + borderPixels: ...
                            xMatch(end) - borderPixels,...
                            :) = bit.*digit;
                        1;
                   end

                    kmlFilename = ['Block_mapping_stack_' num2str(si)];
                    kmlPath = fullfile(kmlDir,kmlFilename);
                    kmlPath = OI.Functions.abspath( kmlPath );
                    kmlPath = [kmlPath '.kml']; %#ok<AGROW>

                    OI.Functions.mkdirs( kmlPath );

                    stackExtent.save_kml_with_image( ...
                        kmlPath, imresize(flipud(map),outputSize,'nearest'));

                end


            end

        end
    end

end
