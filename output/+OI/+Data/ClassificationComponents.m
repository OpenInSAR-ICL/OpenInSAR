classdef ClassificationComponents < OI.Data.DataObj
    properties
        id = 'classcomp_$STACK$_$BLOCK$_$PART$_of_$PARTS$' %_$POLARISATION$
        generator = 'ClassBlock'
        STACK
        BLOCK
        PART
        PARTS
    end
    
    methods
        function this = ClassificationComponents( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/classification/$id$';
            this.fileextension = 'mat';
        end%ctor
    end
end

