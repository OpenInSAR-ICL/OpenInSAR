classdef OrbitFileHttpIndexing < OI.Plugins.PluginBase

properties
    id = 'OrbitFileHttpIndexing'
    inputs = {OI.Data.Catalogue()}
    outputs = {OI.Data.OrbitFileIndex()}
end % properties
%#ok<*DATST> - allow datestr() for Octave

methods
    function this = OrbitFileHttpIndexing
        this.isArray = false;
    
    end
    
    function this = run(this, engine, varargin)
        SITE = 'http://step.esa.int/auxdata/orbits/Sentinel-1/POEORB/';
        
        count = 0;
        h = {};
        n = {};
        
        for sat = ['A' 'B']
        for startYear=2014:2023
            
            
            
            for startMonth=1:12
                startMonth = num2str(startMonth);
                if numel(startMonth)~=2
                    startMonth = ['0' startMonth];
                end
                PAGE = ...
                    [SITE 'S1' sat '/' num2str(startYear) '/' num2str(startMonth)];
                try
                    w = webread(PAGE);
                    links = strsplit(w,'</a>');

                    for ii=1:numel(links)-1
                        lol = strsplit(links{ii},'a href="');
                        rol = strsplit(lol{2},'"');
                        hTemp = rol{1};
                        if numel(hTemp)>4 && all(hTemp(end-3:end)=='.zip')
                            count = count + 1;
                            h{count} = [PAGE '/' hTemp];
                            n{count} = hTemp;
                        end
                    end
                catch
                    fprintf(1,'%s - 404\n',PAGE);
                    % prob 404
                end
            end
        end
        end
        
        this.outputs{1}.links=h;
        this.outputs{1}.filenames=n;
        engine.save( this.outputs{1} )
    end % run(



end % methods

end % classdef

% Response = {"feed":{"xmlns":"http://www.w3.org/2005/Atom","xmlns:opensearch":"http://a9.com/-/spec/opensearch/1.1/","title":"Sentinels GNSS RINEX Hub search results for: (beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))","subtitle":"Displaying 1 results. Request done in 0 seconds.","updated":"2023-03-31T17:00:24.814Z","author":{"name":"Sentinels GNSS RINEX Hub"},"id":"https://scihub.copernicus.eu/gnss/search?q=(beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))","opensearch:totalResults":"1","opensearch:startIndex":"0","opensearch:itemsPerPage":"100","opensearch:Query":{"startPage":"1","searchTerms":"(beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))","role":"request"},"link":[{"href":"https://scihub.copernicus.eu/gnss/search?q=(beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))&start=0&rows=100&format=json","type":"application/json","rel":"self"},{"href":"https://scihub.copernicus.eu/gnss/search?q=(beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))&start=0&rows=100&format=json","type":"application/json","rel":"first"},{"href":"https://scihub.copernicus.eu/gnss/search?q=(beginPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] AND endPosition:[2023-01-29T00:00:00.000Z TO 2023-01-31T23:59:59.999Z] ) AND ( (platformname:Sentinel-1 AND producttype:AUX_POEORB))&start=0&rows=100&format=json","type":"application/json","rel":"last"},{"href":"opensearch_description.xml","type":"application/opensearchdescription+xml","rel":"search"}],"entry":{"title":"S1A_OPER_AUX_POEORB_OPOD_20230219T080751_V20230129T225942_20230131T005942","link":[{"href":"https://scihub.copernicus.eu/gnss/odata/v1/Products('4d94ac07-481d-4470-a01c-3586f27661d3')/$value"},{"rel":"alternative","href":"https://scihub.copernicus.eu/gnss/odata/v1/Products('4d94ac07-481d-4470-a01c-3586f27661d3')/"},{"rel":"icon","href":"https://scihub.copernicus.eu/gnss/odata/v1/Products('4d94ac07-481d-4470-a01c-3586f27661d3')/Products('Quicklook')/$value"}],"id":"4d94ac07-481d-4470-a01c-3586f27661d3","summary":"Date: 2023-01-29T22:59:42Z, Instrument: , Satellite: Sentinel-1, Size: 4.43 MB","ondemand":"false","date":[{"name":"generationdate","content":"2023-02-19T08:07:51Z"},{"name":"beginposition","content":"2023-01-29T22:59:42Z"},{"name":"endposition","content":"2023-01-31T00:59:42Z"},{"name":"ingestiondate","content":"2023-02-19T08:40:11.504Z"}],"str":[{"name":"format","content":"EOF"},{"name":"size","content":"4.43 MB"},{"name":"platformname","content":"Sentinel-1"},{"name":"platformshortname","content":"S1"},{"name":"platformnumber","content":"A"},{"name":"platformserialidentifier","content":"1A"},{"name":"filename","content":"S1A_OPER_AUX_POEORB_OPOD_20230219T080751_V20230129T225942_20230131T005942.EOF"},{"name":"producttype","content":"AUX_POEORB"},{"name":"filedescription","content":"Precise Orbit Ephemerides (POE) Orbit File"},{"name":"fileclass","content":"OPER"},{"name":"creator","content":"OPOD"},{"name":"creatorversion","content":"3.1.0"},{"name":"identifier","content":"S1A_OPER_AUX_POEORB_OPOD_20230219T080751_V20230129T225942_20230131T005942"},{"name":"uuid","content":"4d94ac07-481d-4470-a01c-3586f27661d3"}]}}}
