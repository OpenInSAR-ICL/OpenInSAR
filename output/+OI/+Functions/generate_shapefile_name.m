function fn = generate_shapefile_name(plugin, projObj )

    assert(isa(plugin, 'OI.Plugins.PluginBase'), ...
        'first argument should be an OI.Plugin class')
    fn = fullfile( ...
        projObj.WORK, ...
        'shapefiles', ...
        plugin.id, ...
        plugin.id);

    propsToMap = {'STACK', 'BLOCK', 'VISIT', 'POLARIZATION'};
    for propCell = propsToMap
        prop = propCell{1};
        if isprop(plugin, prop)
            propStr = plugin.(prop);
            if isnumeric(propStr)
                propStr = num2str(propStr);
            end
            fn = [fn '_' prop '_' propStr];  %#ok<AGROW>
        end
    end
    
    fn = [fn '.shp'];
end

