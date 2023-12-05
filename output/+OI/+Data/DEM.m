classdef DEM < OI.Data.DataObj
    properties
        generator = 'GetDEM'
        id = 'DEM'
        tiles = cell(0);
        loaded = cell( 0 );
        extent = OI.Data.GeographicArea();
        source = 'SRTM1';
    end % properties

    % properties (Constant, Hidden = true)
    %     SRTM1_TILE_SZ = [3601,3601];
    %     SRTM3_TILE_SZ = [1201,1201];
    % end
 

    methods
        function this = DEM(varargin)
            this.hasFile = true;
            this.filepath = '$workingDirectory$/DEM';
        end

        function this = add_tile(this, tileFilepath)
            %N52W002.hgt
            this.tiles{end+1} = tileFilepath;
            this.loaded{end+1} = {};

            tileExtent = this.srtm1_tile_extent( tileFilepath );
            this.extent = this.extent.encompass( tileExtent );
            this.extent = this.extent.simplify();
        end
        

        function this = configure(this)
            % check the loaded cell is the right size
            if numel(this.loaded) > numel(this.tiles)
                % dump excess load cells
                this.loaded( numel(this.tiles)+1:end ) = [];
            elseif numel(this.loaded) < numel(this.tiles)
                % add missing load cells
                for missingInd = numel(this.loaded)+1:numel(this.tiles)
                    this.loaded{missingInd} = [];
                end
            end

            % check the extent by encompassing all tiles
            for ii=1:numel(this.tiles)
                tileExtent = this.srtm1_tile_extent(this.tiles(ii));
                this.extent = this.extent.encompass( tileExtent );
            end
            this.extent = this.extent.simplify();
        end

        function [this, tileData] = load_tile(this, tileInd)
            if isempty(this.loaded{tileInd})
                tileData = this.load_srtm1_tile( this.tiles{tileInd} );
                this.loaded{tileInd} = tileData;
            else
                tileData = this.loaded{tileInd};
            end
        end

        function this = unload(this)
            this.loaded = cell( size(this.loaded) );
        end

        function [this, interpolatedHeight] = interpolate( this, lat, lon )

            % get the extent of the points for interpolation
            interpolationExtent = OI.Data.GeographicArea.from_limits( ...
                min(lat), max(lat), ...
                min(lon), max(lon) );

            % Get all the tiles that intersect the interpolation extent
            tileIsIn = zeros(numel(this.tiles),1);
            minMosaicLat = 90;
            maxMosaicLat = -90;
            minMosaicLon = 180;
            maxMosaicLon = -180;
            for ii=1:numel(this.tiles)
                tileExtent = this.srtm1_tile_extent( this.tiles{ii} );
                % if the interpolated area contains the tile or vice versa
                tileIsIn(ii) = ....
                    interpolationExtent.overlaps( tileExtent );
                if tileIsIn(ii)
                    % find the minimum latitude of the tiles we;re going to load
                    minMosaicLat = min( [minMosaicLat; tileExtent.lat(:)] );
                    maxMosaicLat = max( [maxMosaicLat; tileExtent.lat(:)] );
                    minMosaicLon = min( [minMosaicLon; tileExtent.lon(:)] );
                    maxMosaicLon = max( [maxMosaicLon; tileExtent.lon(:)] );
                end
            end

            % find the tiles that contains the point
            tileInds = find(tileIsIn);
            if isempty(tileInds)
                warning('Points are not within the DEM extent');
            end

            % create a grid to hold all the tiles, we will then 
            % add in the tiles
            numTilesInLat = numel(minMosaicLat:1:maxMosaicLat-1);
            numTilesInLon = numel(minMosaicLon:1:maxMosaicLon-1);
            mosaic = zeros( numTilesInLat*3601, numTilesInLon*3601 );
            mosaicLat = linspace(minMosaicLat, maxMosaicLat, numTilesInLat*3601);
            mosaicLon = linspace(minMosaicLon, maxMosaicLon, numTilesInLon*3601);

            % load in the tiles
            for tileInd = tileInds(:)'
                tileExtent = this.srtm1_tile_extent( this.tiles{tileInd} );
                [this, tileData] = this.load_tile(tileInd);

                % find the indices of the tile in the mosaic
                latInds = find( mosaicLat >= min(tileExtent.lat) & ...
                                mosaicLat <= max(tileExtent.lat) );
                lonInds = find( mosaicLon >= min(tileExtent.lon) & ...
                                mosaicLon <= max(tileExtent.lon) );


                % add the tile to the mosaic
                % FNDSB: logical array wouldnt work as its 2d...
                mosaic( latInds, lonInds ) = tileData;%#ok<FNDSB>
                % imagesc(mosaicLon,mosaicLat,mosaic); set(gca,'YDir','normal')
                % pause(1)
            end

            % interpolate the point
            interpolatedHeight = interp2(mosaicLon,mosaicLat,mosaic, ...
                lon(:),lat(:));
        end
    end % methods

    methods (Static = true)
        function extent = srtm1_tile_extent( filename )
            %N52W002.hgt -> [51 52 -2 -1]
            [~, name, ext] = fileparts( filename );
            if ~strcmp(ext, '.hgt')
                error('Invalid file extension: %s', ext);
            end

            % pull out the lat/lon
            latSign = -2 * strcmp(name(1), 'S') + 1;
            lonSign = -2 * strcmp(name(4), 'W') + 1;
            lat = str2double(name(2:3)) * latSign;
            lon = str2double(name(5:7)) * lonSign;

            extent = OI.Data.GeographicArea.from_limits( ...
                lat, lat+1, ...
                lon, lon+1);
        end

        function tileData = load_srtm1_tile( filename )
            % load in the data from the .hgt file
            fid = fopen(filename, 'r', 'ieee-be');
            if fid == -1
                warning('Could not open file: %s', filename);
                tileData = -ones(3601,3601,'like',int16(1));
                % Don't return. We still want to adjust for geoid to avoid
                % jumps. Then we can check for sea via: 
                %(dem -lt geoid_height)
                % return;
            else
                tileData = fread(fid, [3601,3601], 'int16=>int16');
                tileData = flipud(tileData.');
                fclose(fid);
            end
            
            % Get coordinates from filename
            extent = OI.Data.DEM.srtm1_tile_extent(filename);
            latAxis=linspace(extent.south(),extent.north(),3601);
            lonAxis=linspace(extent.west(),extent.east(),3601);
            [lon, lat] = meshgrid(lonAxis,latAxis);
%             return
            geoidAtGrid = OI.Data.DEM.get_geoid_height(lat,lon);

%             % Calculate geoid undulation (mean sea level) at coordinates
%             geoidAtExtentBoundaries = get_geoid_height(extent.lat, extent.lon, 'EGM96');
% 
%             % Fit a 2d linear polynomial to the geoid undulation at the extent
%             nSamples = numel(geoidAtExtentBoundaries(:));
%             geoidFitCoefficients = [extent.lat(:), extent.lon(:), ones(nSamples,1)] \ geoidAtExtentBoundaries(:);
% 
%             % Interpolate the geoid undulation on the grid
%             geoidAtGrid = [lat(:), lon(:), ones(numel(lat),1)] * geoidFitCoefficients;
%             geoidAtGrid = reshape(geoidAtGrid,size(tileData));
            
            % Remove geoid undulation (mean sea level) from elevation data
            tileData = tileData + int16(geoidAtGrid); % [m] 
        end
        
        function interpHeight = get_geoid_height( queryLat, queryLon)

            % Replace this with your actual data or computation based on the provided model
            geoidHeight = OI.Data.DEM.get_geoid();
            lat = linspace(-92,92,737);
            lon = linspace(-2,362,1457);
                
            assert( all(queryLat(:)>-90) && all(queryLat(:)<90) && all(queryLon(:)>-180) && all(queryLon(:)<180) );
            queryLon(queryLon<0) = 360 + queryLon(queryLon<0);
            % Perform 2D cubic interpolation
            interpHeight = interp2(lon, lat, geoidHeight, queryLon, queryLat, 'cubic');
        end 
        % eGm96 https://geographiclib.sourceforge.io/cgi-bin/GeoidEval
        % 54, -3 : 52.61
        % 51, 0 : 45.2995
        % 55.1 0.5 : 46.07
        
        
        function data = get_geoid()
            persistent geoidGrid
            if isempty(geoidGrid)
                % Lazy loading of the data file
                geoidGrid = load('egm96.mat');
            end
            data = geoidGrid.egm96;
        end
    end % methods (Static = true)

end % classdef