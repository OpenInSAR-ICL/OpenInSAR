function tilepaths = get_srtm_tiles(minLat, maxLat, minLon, maxLon, directory, username, password)
    % address for srtm download
    % note trailing /
    NASA_URL = 'https://e4ftl01.cr.usgs.gov/MEASURES/SRTMGL1.003/2000.02.11/'; 

    if nargin < 5
        directory = fullfile(pwd,'srtm1');
    end
    % make sure the directory exists
    if ~exist(directory,'dir')
        OI.Functions.mkdirs(fullfile(directory,'1'));
    end

    % SRTM1_TILE_SZ = [3601,3601]; % SRTM1 tile size
    
    %SRTM is in integer lat/lon squares
    latIntegers = floor(minLat):floor(maxLat);
    lonIntegers = floor(minLon):floor(maxLon);

    % Get all the tiles needed via meshgrid
    [latGrid,lonGrid] = meshgrid(latIntegers,lonIntegers);
    lat = latGrid(:);
    lon = lonGrid(:);

    % files to download and save
    tilenames = cell(size(lat));
    tileurls = cell(size(lat));

    % Result cell:
    tilepaths = cell(size(lat));
    
    % Name format:
    hgtFormatStr = '%s%s.hgt';
    urlFormatStr = '%s%s%s.SRTMGL1.hgt.zip';
    % Determine the formatted filename
    for n = 1:numel(tilenames)
        if lat(n) < 0
            slat = sprintf('S%02d',-lat(n));
        else
            slat = sprintf('N%02d',lat(n));
        end
        if lon(n) < 0
            slon = sprintf('W%03d',-lon(n));
        else
            slon = sprintf('E%03d',lon(n));
        end
        tilenames{n} = sprintf(hgtFormatStr,slat,slon);
        tileurls{n} = sprintf(urlFormatStr,NASA_URL,slat,slon);
        tilepaths{n} = fullfile(directory, tilenames{n});
    end % for each tile

    % Define status arrays for array of tiles
    [fileExists, zipExists, needsUnzip, needsDownload, downloadFailed] = ...
        deal(zeros(n,1) == 42);
    
    for n = 1:numel(tilepaths)
        fileExists(n) = exist(tilepaths{n},'file') > 0;
        zipExists(n) = exist([tilepaths{n},'.zip'],'file') > 0;
        
        needsDownload(n) = ~zipExists(n) && ~fileExists(n);
        needsUnzip(n) = needsDownload(n) || (zipExists(n) && ~fileExists(n));
    end

    % download and unzip the file
    needsDownload=needsDownload+1;
    for n = 1:numel(tilepaths)
        if needsDownload(n)
            remoteaddress = tileurls{n};
            localaddress = [tilepaths{n}, '.zip'];
            try
                if OI.OperatingSystem.isUnix
                    wgetCommand = sprintf( ...
                        'wget -c -q -O %s --user=%s --password=%s %s --no-check-certificate', ...
                        localaddress, username, password, remoteaddress);
                    [s,w] = system(wgetCommand);
                    
                    if s==6
                        error( [ 'USERNAME/PASSWORD ERROR ' ...
                                ' URL:\n%s\nUSERNAME: %s' ], ...
                                NASA_URL, ...
                                username );
                    elseif s % not sure how we branch here, throw a warning
                        warning('Error code %d',s);
                        disp(w);
                    end
                elseif OI.OperatingSystem.isWindows
                    % Create an HTTP options object with basic authentication
                    options = weboptions( ...
                        'Username', username, 'Password', password);
                    demBinary = webread(remoteaddress, options);
                    fid = fopen(localaddress,'w');
                    sc = fwrite(fid, demBinary, 'uint8');
                    fclose(fid);
                end
                % Regardless of OS, we need a file...
                if ~exist(localaddress,'file')
                    needsUnzip(n) = false;
                    error('No file available for %s',localaddress)
                end
            catch ERR
                warning('Failed to download SRTM tile %s from %s .', ...
                    localaddress, remoteaddress);
                downloadFailed(n) = true;
            end
        end % if needsDownload

        if needsUnzip(n) && ~downloadFailed(n)
            inputPath = [tilepaths{n}, '.zip'];
            if OI.OperatingSystem.isUnix
                unzipCommand = sprintf('unzip -DD -o %s -d %s', ...
                    inputPath, ...
                    directory ...
                );
            else
                unzipCommand = sprintf('powershell -Command "Expand-Archive -Path ''%s'' -DestinationPath ''%s''"', inputPath ,directory);
            end

            [s,w] = system(unzipCommand);
            if s
                disp(w)
                % rename the failed zip file
                oneInAMillion = num2str(floor(mod(now(),1)*1000000));
                movefile([tilepaths{n}, '.zip'], ...
                    [tilepaths{n}, '.zip.failed', oneInAMillion]);
                warning('SRTM tile could not be downloaded. Maybe in sea? - %s', tilepaths{n})
            else
                % delete the zip
                delete([tilepaths{n}, '.zip']);
                fileExists(n) = true;
            end
        end % if needsUnzip and not downloadFailed

    end % for each tile
    % !TODO
    % The really quick & dirty solution to sea/404 is just return the filepath to
    % a file we already have... its not being used anyway as no coherence
    % in sea. If we start looking at wind turbines thats obviously a
    % problem.
    if any(fileExists)
        hack = find(fileExists,1);
        for n = reshape(find(downloadFailed),1,[])
            copyfile(tilepaths{hack}, tilepaths{n});
        end
    else
        error('failed to find any srtm files')
    end
end

%#ok<*TNOW1> - Octave compatibility


