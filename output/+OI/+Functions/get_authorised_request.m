function requestObject = get_authorised_request(URL, username, password)

    requestObject = matlab.net.http.RequestMessage('POST');

    LOGIN_URL = [URL, 'login/'];
    CSRF_URL = [URL, 'csrf/'];

    % Step 1: Initialize the CSRF request message
    reqCsrf = matlab.net.http.RequestMessage('GET');
    opts = matlab.net.http.HTTPOptions();
    opts.CertificateFilename = '';

    % Step 2: Get the CSRF token
    res = reqCsrf.send(CSRF_URL, opts);
    cookieHeaderInd = find(arrayfun(@(x) strcmpi(x.Name,'Set-Cookie'), res.Header));
    cookieStr = res.Header(cookieHeaderInd).Value;
    csrfToken = res.Body.Data.csrfToken;

    % Step 3: Update headers with the CSRF token for login request
    cookieStr = strrep(cookieStr,'SameSite=Lax','');
    sessionid = regexp(cookieStr, 'sessionid=([a-zA-Z0-9\-]+)', 'tokens', 'once');
    sessionid = sessionid{1}; % Extract the sessionid value
    cookieStr = ['sessionid=' sessionid];
    
    % Step 4, perform login request
    body = matlab.net.http.MessageBody(struct('username', username, 'password', password));
    reqLogin = matlab.net.http.RequestMessage('POST');
    reqLogin.Body = body;
    reqLogin.Header =  matlab.net.http.HeaderField('Content-Type', 'application/json','X-CSRFToken', csrfToken,'Referer', URL,'Cookie', cookieStr);
    resLogin = reqLogin.send(LOGIN_URL, opts);
   
    % Step 5: Get new session cookie (post-login)
    cookieHeaderInd = find(arrayfun(@(x) strcmpi(x.Name, 'Set-Cookie'), resLogin.Header));
    cookieStr = resLogin.Header(cookieHeaderInd).Value;
    sessionid = regexp(cookieStr, 'sessionid=([a-zA-Z0-9\-]+)', 'tokens', 'once');
    sessionid = sessionid{1}; % Extract the sessionid value
    cookieStr = ['sessionid=' sessionid];
    
    % Step 6: Get new CSRF token (after login)
    reqCsrfNew = matlab.net.http.RequestMessage('GET');
    reqCsrfNew.Header = matlab.net.http.HeaderField('Cookie', cookieStr);
    resCsrfNew = reqCsrfNew.send(CSRF_URL, opts);
    csrfTokenNew = resCsrfNew.Body.Data.csrfToken; % New CSRF token

    % Return the upload request object
    requestObject.Header = ...
        matlab.net.http.HeaderField('Content-Type', 'application/json','X-CSRFToken', csrfTokenNew,'Referer', URL,'Cookie', cookieStr);
    

end

