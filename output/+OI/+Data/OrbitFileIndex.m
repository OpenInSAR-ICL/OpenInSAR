classdef OrbitFileIndex < OI.Data.DataObj

properties
    id = 'OrbitFileIndex'
    generator = 'OrbitFileHttpIndexing';
    links = {};
    filenames = {};
    
end%properties

methods
    function this = OrbitFileIndex( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/$id$';
        this.fileextension = 'mat';
        this.isUniqueName = true;
    end%ctor
    
    function this = download_from_catalogue(this, engine, cat)
        if ~exist(engine.database.fetch('ORBITS_DIR'),'dir')
            mkdir(engine.database.fetch('ORBITS_DIR'));
        end
        oDir = engine.database.fetch('ORBITS_DIR');
        
        startDates=zeros(numel(this.filenames),1);
        endDates=startDates;
        for jj=1:numel(this.filenames)
            [startDates(jj), endDates(jj)] = this.get_start_end_from_fn(this.filenames{jj});
        end
        
        for ii=1:numel(cat.safes)
            %fprintf(1,'%i - %f \n',ii,ii/numel(cat.safes));
            targetDatetime = cat.safes{ii}.date;
            % get the platform
            targetPlatform = cat.safes{ii}.platform;
            
            for jj = 1:numel(this.filenames)
                fn = this.filenames{jj};
                % This initial filter speeds things up
                if abs(startDates(jj) - targetDatetime.daysSinceZero) > 2
                    continue
                end
                
                
                if this.compare( targetPlatform, targetDatetime, fn)
                    link = this.links{jj};
                    ff = [oDir '/' fn];
                    if exist(ff,'file') || exist(strrep(ff,'.zip',''),'file')
                        continue
                    end
                    unzip(link, oDir)
                end
            end
        end
        
        % copy the tmp folder to oDir
        % copyfile([oDir '/tmp/*'],oDir);
    end
    
end%methods

methods (Static = true)
    function tf = compare(tPlatform,tDatetime,filename)
        tf = false;
        if ~strcmpi(filename(1:3),tPlatform)
            return
        end
        splitty = strsplit(filename,{'_V','.EOF','_'});
        startDate = datenum(splitty{7},'yyyymmddTHHMMSS');
        endDate = datenum(splitty{8},'yyyymmddTHHMMSS');
        
        
        if tDatetime.daysSinceZero > startDate && ...
                tDatetime.daysSinceZero < endDate
            tf = true;
        end

    end
    
    function [startDate, endDate] = get_start_end_from_fn(filename)
        splitty = strsplit(filename,{'_V','.EOF','_'});
        startDate = datenum(splitty{7},'yyyymmddTHHMMSS');
        endDate = datenum(splitty{8},'yyyymmddTHHMMSS');
    end
end
end%classdef