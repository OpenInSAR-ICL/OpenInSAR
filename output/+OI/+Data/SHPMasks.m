classdef SHPMasks < OI.Data.DataObj
    properties
        id = 'SHPMasks_stack_$STACK$_BLOCK_$BLOCK$'
        generator = 'IdentifySHP'
        STACK
        BLOCK
        masks
        pValues
    end

    methods
        function this = SHPMasks()
            this.filepath = '$WORK$/DS/$id$';
            this.fileextension = 'mat';
            this.hasFile = true;
        end
    end
end
