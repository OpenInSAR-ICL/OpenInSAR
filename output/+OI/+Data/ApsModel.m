classdef ApsModel < OI.Data.DataObj
    properties
        STACK
        rgGrid
        azGrid
        phase
        timeSeries
        referencePhase
        referenceAddress
        info
        id = 'aps_model_stack_$STACK$'
        generator = 'ApsKriging'
    end
    
    methods
        function this = ApsModel( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/aps/$id$';
            this.fileextension = 'mat';
        end%ctor
    end
end

