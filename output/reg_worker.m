adr = "http://localhost:8765/api";
setenv("OI_USERNAME", "test_user");
setenv("OI_PASSWORD", "test_password");
setenv("OI_SERVER", adr);
setenv("OI_MESSENGER", "http");


% Create the Http interface and log in using the envvars above.
m = OI.HttpMessenger(adr).connect()
% Register the worker
startList = m.send_request('workers','','get')
postRespose = m.send_request('workers',{'octave_query=true&worker_id=Colin'},'post')
updatedList = m.send_request('workers','','get')
% Bilbo should now be in updatedList
