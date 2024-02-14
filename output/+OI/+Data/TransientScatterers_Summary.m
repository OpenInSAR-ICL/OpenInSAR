classdef TransientScatterers_Summary < OI.Data.DataObj

    properties
        id = 'TransientScatterers_Summary';
        generator = 'TransientScatterers';
    end % properties

    methods
        function this = TransientScatterers_Summary(~)
            this.hasFile = true;
            this.filepath = '$WORK$/$id$';
        end % ctor
    end % methods

end % classdef
