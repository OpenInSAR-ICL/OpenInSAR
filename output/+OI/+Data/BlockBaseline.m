classdef BlockBaseline < OI.Data.DataObj

properties
    % name = 'AsfQueryResults';
    id = 'stack_$STACK$_block_$BLOCK$_baseline_information';
    generator = 'BlockBaselineAnalysis';
    STACK;
    BLOCK;

    k;
    spatialBaseline
    perpendicularBaseline;
    sensingVector;
    azimuthVector;
    perpendicularVector;
    orbitXYZ;
    blockXYZ;
    blockInfo;
    timeSeries;
    
    heading;
    direction;
    meanIncidenceAngle;

end%properties

methods
    function this = BlockBaseline( ~ )
        this.hasFile = true;
        this.filepath = '$WORK$/blocks/baseline/$id$';
        this.fileextension = 'mat';
    end%ctor
end%methods

end