function response = send_authorised_request(ROOT_URL, username, password, endpoint, data, endpointExpectsArray)
% EXAMPLE:
% myData = {struct( ...
% 'dataset', 2, ...
% 'location', [0.31, 0.45], ...
% 'time_series_values', [1.1, 1.2, 123], ...
% 'coherence', 0.5, ...
% 'velocity', 0.6, ...
% 'height_error', 123 ...
% )};
% OI.Functions.send_authorised_request('https://localhost/api/','myUsername','myPassword','psi-info-upload/',myData)

URL = [ROOT_URL, endpoint];
request = OI.Functions.get_authorised_request(ROOT_URL, username, password);

if nargin<=5 
    endpointExpectsArray = true;
end
if endpointExpectsArray
    request.Body = matlab.net.http.MessageBody({data});
else
    request.Body = matlab.net.http.MessageBody(data);
end
response = request.send(URL,matlab.net.http.HTTPOptions('CertificateFilename',''));

end

