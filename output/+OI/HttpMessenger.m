classdef HttpMessenger < OI.MessengerBase
% HttpMessenger: A class for sending and receiving messages via HTTP.
% takes a server address as constructor argument
% methods:
%  send: send a message to the server
%  receive: receive a message from the server

properties
  serverAddress = ''
  token = ''
end % properties

methods
    function obj = HttpMessenger(serverAddress)
        % constructor
        obj.serverAddress = serverAddress;
    end % constructor

    function response = send(obj, messageObj)
        % Send an OI.Message object
        % message: the message to send

        % assert that the message is an OI.Message object
        if ~isa(messageObj, 'OI.Message')
            error('Message must be an OI.Message object. For more granular control, use send_request()');
        end

        response = obj.send_request( ...
            messageObj.endpoint, ...
            messageObj.content, ...
            messageObj.httpMethod,...
            messageObj.contentType);
    end % function

    function response = send_request(obj, endpoint, content, httpMethod, contentType)
        % Sends the message to server/endpoint using the specified httpMethod and with content type contentType
        % endpoint: the endpoint to send the message to, added to the server address specified when constructing this object
        % message: the message to send
        % httpMethod: the HTTP httpMethod to use, one of GET, POST, PUT, DELETE
        % contentType: the contentType to use, one of JSON, XML, TEXT

        options = weboptions();

        % check args and set defaults
        if nargin>1 % endpoint
            if ~ischar(endpoint)
                error('Endpoint must be a string');
            end
            uri = obj.format_uri(endpoint);
        else
            error('no endpoint specified')
        end

        if nargin>2 % content
            if ~ischar(content) && ~iscellstr(content) && ~isstring(content)
                error('Content must be stringy, or cell array of stringys');
            end
        else % default content
            content = '';
        end

        if nargin>3 % httpMethod
            if ~ischar(httpMethod)
                error('Method must be a string');
            end
            options.RequestMethod = lower(httpMethod);
        else % default http method
            options.RequestMethod = 'post';
        end

        if nargin>4 % contentType
            if ~ischar(contentType)
                error('Protocol must be a string');
            end
        else % default content type
            contentType = 'JSON';
        end

        % set the content type
        switch upper(contentType)
        case 'JSON'
            options.MediaType = 'application/json';
        case 'XML'
            options.MediaType = 'application/xml';
        case 'TEXT'
            options.MediaType = 'text/plain';
        otherwise
            error('Invalid contentType');
        end

        % switch httpMethod
        % case 'GET'
        %     % send message via GET
        %     options.RequestMethod = 'get';
        % case 'POST'
        %     % send message via POST
        %     options.RequestMethod = 'post';
        % case 'DELETE'
        %     % send message via DELETE
        %     options.RequestMethod = 'delete';
        % case 'PUT'
        %     % send message via PUT
        %     options.RequestMethod = 'put';
        % otherwise % POST
        %     error('Invalid httpMethod');
        % end

        % send the message
        if iscell(content)
            response = webwrite(uri, content{:}, options);
        else
            response = webwrite(uri, content, options);
        end

    end % send

    function response = receive(~, endpoint)
        % send a GET request to the server
        response = self.send(endpoint, '', 'GET');
    end % receive

    function obj = connect(obj)
        % Login
        username = getenv('OI_USERNAME');
        password = getenv('OI_PASSWORD');
        content = ['username=' username '&password=' password];
        options = weboptions();
        options.RequestMethod = 'post';
        login_path = 'login';
        uri = obj.format_uri(login_path);
        response = webwrite(uri, content, options);
        % conver json to struct
        response = jsondecode(response)
        obj.token = response.token;

    end % connect

    function obj = disconnect(obj)
        % Not needed for HTTP
    end % disconnect

    function uri = format_uri(obj, endpoint)
        % Correctly formats the URI for the GET request, paying attention to the slashes
        % Remove trailing slash from server address
        if numel(obj.serverAddress) && obj.serverAddress(end) == '/'
            obj.serverAddress = obj.serverAddress(1:end-1);
        end
        % check if the endpoint starts with a slash
        if numel(endpoint) && endpoint(1) == '/'
            uri = [obj.serverAddress, endpoint];
        else
            uri = [obj.serverAddress, '/', endpoint];
        end
        % Check uri is valid
        if numel(uri) < 2
            error('Invalid URI format');
        end
    end % format_uri

end % methods


end % classdef
