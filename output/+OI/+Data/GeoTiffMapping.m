classdef GeoTiffMapping < OI.Data.DataObj

properties
    % name = 'AsfQueryResults';
    id = 'GeoTiffMapping_stack_$STACK$_seg_$SEGMENT$';
    generator = 'GeoTiffs';
    STACK = '';
    SEGMENT = '';
    weights = [];
    closestIndices = [];
    inputSize = [];
    inputFile = '';
    outputSize = [];
    distance = []; % average distance from interpolated points
    
end%properties

methods
    function this = GeoTiffMapping( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/geotiffs/$id$';
        this.fileextension = 'mat';
        this.isUniqueName = true;
    end
end%methods

end%classdef