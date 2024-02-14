classdef BufferedBlock < OI.Data.DataObj
    properties
        id = 'BufferedBlock_s$STACK$_b$BLOCK$_p$POLARISATION$_w$WAZ$_$WRG$'
        generator = 'GetFieldSamples'
        STACK
        BLOCK
        POLARISATION
        WAZ
        WRG
    end
    
    methods
        function this = BufferedBlock( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/BufferedBlocks/$id$';
            this.fileextension = 'mat';
        end%ctor
    end
end

