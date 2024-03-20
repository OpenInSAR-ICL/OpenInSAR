classdef PersistentScatterersInversionSummary < OI.Data.DataObj
    properties
        generator = 'PersistentScatterersInversion'
        id = 'PersistentScatterersInversionSummary'
    end % properties

    methods
        function this = PersistentScatterersInversionSummary(varargin)
            this.hasFile = true;
            this.filepath = '$WORK$/PSI_Results_Summary';
        end
    end % methods
end % classdef
