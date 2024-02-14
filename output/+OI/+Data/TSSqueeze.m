classdef TSSqueeze < OI.Data.DataObj
    properties
        id = 'TSSqueeze_$STACK$_$BLOCK$' %_$POLARISATION$
        generator = 'GetFieldSamples'
        STACK
        BLOCK
    end
    
    methods
        function this = TSSqueeze( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/TSSqueeze/$id$';
            this.fileextension = 'mat';
        end%ctor
        
        function partString = part_string(this, part, numberOfParts)
            partString = sprintf('_%iof%i', part, numberOfParts);
        end
        
        function this = part(this, part, numberOfParts)
            this.id = [this.id this.part_string(part, numberOfParts)];
        end
    end
end

