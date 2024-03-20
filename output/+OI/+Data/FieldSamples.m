classdef FieldSamples < OI.Data.DataObj
    properties
        id = 'field_samples_$STACK$_$BLOCK$' %_$POLARISATION$
        generator = 'GetFieldSamples'
        STACK
        BLOCK
        POLARISATION
    end
    
    methods
        function this = FieldSamples( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/fields/$id$';
            this.fileextension = 'mat';
        end%ctor
    end
end

