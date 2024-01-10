classdef MessengerBase

    methods (Abstract)
        function send(~, ~)
        end

        function this = connect(~, ~)
        end
    end

end % classdef