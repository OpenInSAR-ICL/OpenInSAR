function datasetId = get_dateset_id(engine, ROOT_URL, stack, block)
    if nargin == 0
        error('You need args')
    end
    projObj = engine.load( OI.Data.ProjectDefinition());
    baselinesObjectTemplate = OI.Data.BlockBaseline().configure( ...
        'STACK', num2str(stack), ...
        'BLOCK', num2str(block) ...
    ).identify(engine);
    baselinesObject = engine.load(baselinesObjectTemplate);
    if isempty(baselinesObject)
        error('No baseline data for defining dataset')
    end
    stacks = engine.load(OI.Data.Stacks);
    if isempty(stacks)
        error('No stack data for defining dataset')
    end


    t0 = baselinesObject.timeSeries;
    aoi = projObj.AOI; % Assuming projObj.AOI is a structure with the limits
    wkt = sprintf('POLYGON((%f %f, %f %f, %f %f, %f %f, %f %f))', ...
        aoi.westLimit, aoi.northLimit, ...  % First corner (west, north)
        aoi.eastLimit, aoi.northLimit, ...  % Second corner (east, north)
        aoi.eastLimit, aoi.southLimit, ...  % Third corner (east, south)
        aoi.westLimit, aoi.southLimit, ...  % Fourth corner (west, south)
        aoi.westLimit, aoi.northLimit);     % Closing the polygon (west, north)
    

    opts = matlab.net.http.HTTPOptions('CertificateFilename','');
    authorised_request = OI.Functions.get_authorised_request(ROOT_URL, 'stew', '4040');
    authorised_request.Method = 'get';
    sitesResponse = authorised_request.send([ROOT_URL 'sites/'],opts);

    % // make a site if not exits
    sites = sitesResponse.Body.Data;
    site_name = regexprep(projObj.PROJECT_NAME, '\d+$', '');
    site_locations = [[sites.centre_lat]', [sites.centre_lon]'];
    aoi = projObj.AOI;
    this_location = [(aoi.northLimit +aoi.southLimit)/2 (aoi.westLimit +aoi.eastLimit)/2];
    dist = OI.Functions.haversine(site_locations,this_location);
    [md, mdi] = min(dist);
    thisSite = sites(mdi);

    
    % data = {'name', [site_name,'project'],'author',1};
    % authorised_request.Body = matlab.net.http.MessageBody()
    authorised_request.Method = 'get';
    projectsResponse = authorised_request.send([ROOT_URL 'projects/'],opts);
    projects = projectsResponse.Body.Data;
    thisProject = [];
    for ii = 1:numel(projects)
        if projects(ii).area_of_interest == thisSite.id
            thisProject = projects(ii);
            break
        end
    end
    if isempty(thisProject)
        error("PROJECT NOT FOUND")
    end

    sd = datestr(t0(1),'yyyy-mm-dd');
    ed = datestr(t0(end),'yyyy-mm-dd');
    dataset.name = [thisSite.name ' Track ' num2str(stacks.stack(stack).track) ' PSI ' sd ' to ' ed];
    dataset.site = thisSite.id;
    dataset.project = thisProject.id;
    % dateseries=['"' datestr(t0(1),'yyyy-mm-dd') '"'];
    % for ii=2:numel(t0)
        % dateseries = [ dateseries ', "' datestr(t0(ii),'yyyy-mm-dd') '"'];
    % end
    % dataset.date_series = ['' dateseries ''];
    dateseries = {};
    for ii=1:numel(t0)
        dateseries{ii} = datestr(t0(ii),'yyyy-mm-dd');
    end
    dataset.date_series = dateseries;
    dataset.date_series_length = numel(t0);
    dataset.extent = wkt;

    getDatasets = authorised_request.send([ROOT_URL 'psi-datasets/'],opts);

    % check project doesnt exist already
    oldDatesets = getDatasets.Body.Data;
    postNewDataset = true;
    datasetId = -1;
    for ii = 1:numel(oldDatesets)
        ds = oldDatesets(ii);
        if strcmpi(ds.name, dataset.name)
            datasetId = ds.id;
            postNewDataset = false;
        end
    end

    if postNewDataset
        authorised_request.Method = 'post';
        authorised_request.Body = matlab.net.http.MessageBody(dataset);
        projectsResponse = authorised_request.send([ROOT_URL 'psi-datasets/'],opts);
        datasetId = projectsResponse.Body.Data.id;
    end

end 