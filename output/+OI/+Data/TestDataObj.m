classdef TestDataObj < OI.Data.DataObj
    properties
        generator = 'TestPlugin'
        id = 'TestDataObj_$exampleIndex$'
        exampleIndex
    end % properties

    methods
        function this = TestDataObj( ~ )
            this.hasFile = true;
            this.filepath = '$WORK$/TestDataObj/$id$';
            this.fileextension = 'mat';
        end%ctor
    end % methods
end % classdef