classdef GeoTiffMapping < OI.Data.DataObj

properties
    % name = 'AsfQueryResults';
    id = 'GeoTiffMapping';
    generator = 'GeoTiffs';
    STACK = '';
    SEGMENT = '';
    weights = [];
    closestIndices = [];
    nWidth = [];
    nHeight = [];
    distance = []; % average distance from interpolated points
    
end%properties

methods
    function this = GeoTiffMapping( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/geotiffs/$id$_$STACK$_$SEGMENT$';
        this.fileextension = 'mat';
        this.isUniqueName = true;
    end
end%methods

end%classdef