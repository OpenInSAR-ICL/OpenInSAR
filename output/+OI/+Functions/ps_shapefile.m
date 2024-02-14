function ps_shapefile(filename,latArray,lonArray,dataArray,imageDates,h,v,c, L, N)

OI.Functions.mkdirs(filename);
% add '.shp' to filename if it doesn't already have it
if numel(filename)>4 && ~strcmp(filename(end-3:end),'.shp')
    filename=[filename '.shp'];
end

if ~exist('L','var')
    L = 0.*v;
end
if ~exist('N', 'var')
    N = 0.*v;
end

% if ~isempty(dataArray)
%     % Make a template structure to speed things up
% end

nP=numel(latArray);
nT=size(dataArray,2);
if nP==0
    % Write an empty file
    fid = fopen(filename,'w');
    fclose(fid);
    return
end

for ii=nP:-1:1
    DataStructure(ii).Geometry='Point';
    DataStructure(ii).Lat=latArray(ii);
    DataStructure(ii).Lon=lonArray(ii);
    DataStructure(ii).CODE=['p' num2str(ii)];
    DataStructure(ii).HEIGHT=h(ii);
    DataStructure(ii).H_STDEV=L(ii);
    DataStructure(ii).VEL=v(ii);
    DataStructure(ii).V_STDEV=0;
    DataStructure(ii).COHERENCE=c(ii);
    DataStructure(ii).EFF_AREA=N(ii);

    if ~isempty(dataArray)
        for jj=1:nT
           DataStructure(ii).(['D' imageDates{jj}])=dataArray(ii,jj);
        end
    end
end


OI.Functions.buffer_shpwrite(DataStructure,filename);