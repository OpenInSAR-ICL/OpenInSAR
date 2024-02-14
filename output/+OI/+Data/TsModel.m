classdef TsModel < OI.Data.DataObj
    properties
        id = 'TsModel_stack_$STACK$' % _K_$K$'
        generator = 'TsModel'
        STACK
        K
        nComp
        ccm
        label_components
        n
        nPerLabel
    end

    methods
        function this = TsModel()
            this.filepath = '$WORK$/TsModel/$id$';
            this.fileextension = 'mat';
            this.hasFile = true;
        end
        
        function [correctionCM, label] = get_correction_cm(this, components )
            compdiff = this.label_components - components;
            sumSquare = sum(compdiff.^2,2);
            [~, label] = min(sumSquare);
            correctionCM = this.ccm(:,:,label);
        end
    end
end
