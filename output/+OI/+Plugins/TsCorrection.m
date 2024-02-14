classdef TsCorrection < OI.Plugins.PluginBase
properties
    inputs = {OI.Data.BlockPsiSummary}
    outputs = {OI.Data.TsCorrectionSummary()}
    id = 'TsCorrection'
    STACK 
    BLOCK
    PART
    PARTS = 10;
end

methods
    function this = TsCorrection( varargin )
        this.isArray = true;
    end
    
function this = run(this, engine, varargin)
    if isempty(this.STACK) || isempty(this.BLOCK)
        this = this.queue_jobs(engine);
        return;
    end
    
    if isempty(this.PART)
        this = this.finalise_block(engine);
        return
    end
    this = this.squeeze_portion(engine);
    this.isFinished = true;
end %run

function partInds = part_inds(this, nElements)
    partEnds = floor(linspace(1,nElements+1,this.PARTS+1));
    partInds = partEnds(this.PART):partEnds(this.PART+1)-1;
end

function this = squeeze_portion(this, engine)
    windowSize = [5 21];

    baselinesObject = engine.load( ...
        OI.Data.BlockBaseline().configure( ...
            'STACK', num2str(this.STACK), ...
            'BLOCK', num2str(this.BLOCK) ...
        ) ...
    );
    kFactors = baselinesObject.k(:)';
    timeSeries = baselinesObject.timeSeries(:)';

    lambda = 0.0555;
    phasePerMetersPerYear = (1/365.25) * 2 * (1/lambda) * (2*pi);
    vPhiTs = phasePerMetersPerYear .* timeSeries;

    bBlockObjV = OI.Data.BufferedBlock().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK, ...
        'POLARISATION', 'VV', ...
        'WAZ', windowSize(1), ...
        'WRG', windowSize(2));
    dataVV = engine.load(bBlockObjV);

    bBlockObjH = OI.Data.BufferedBlock().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK, ...
        'POLARISATION', 'VH', ...
        'WAZ', windowSize(1), ...
        'WRG', windowSize(2));
    dataVH = engine.load(bBlockObjH);

    nDays = size(dataVV,2);

    if isempty(dataVV) || isempty(dataVH)
        return
    end
    
    tsModelObj = OI.Data.TsModel().configure( ...
        'STACK', this.STACK ...
    );
    tsModel = engine.load(tsModelObj);
    if isempty(tsModel)
        return
    end

    blockMap = engine.load( OI.Data.BlockMap() );
    blockSize = blockMap.stacks(this.STACK).blocks(this.BLOCK).size;
    projObj = engine.load( OI.Data.ProjectDefinition() );

    % Classify, correct, squeeze
    partInds = this.part_inds(prod(blockSize(1:2)));
    nPartSamples = numel(partInds);
    [indsInBufferedBlock, maskIndex] = this.get_inds_in_buffered_block(engine, blockSize, windowSize, partInds);

    resultPartTemplate = OI.Data.TSSqueeze().configure('STACK',this.STACK,'BLOCK',this.BLOCK).part(this.PART,this.PARTS);
    
    if resultPartTemplate.identify(engine).exists
        resultPartStruct = engine.load( resultPartTemplate );
        qCorrected = resultPartStruct.heightError_corrected;
        vCorrected = resultPartStruct.velocity_corrected;
        cvCorrected = resultPartStruct.coherence_corrected;

        qUncorrected = resultPartStruct.heightError_uncorrected;
        vUncorrected = resultPartStruct.velocity_uncorrected;
        cvUncorrected = resultPartStruct.coherence_uncorrected;
        
        labels = resultPartStruct.LABELS;
        nShps = resultPartStruct.nShps;
    else
        
    resultPartStruct = struct( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK, ...
        'PART', this.PART, ...
        'PARTS', this.PARTS, ...
        'LABELS', zeros(nPartSamples,1), ...
        'CORRECTED', zeros(nPartSamples,nDays), ...
        'UNCORRECTED', zeros(nPartSamples,nDays), ...
        'nShps', zeros(nPartSamples,1), ... % number of samples in shp window
        'heightError_corrected', zeros(nPartSamples,1), ...
        'velocity_corrected', zeros(nPartSamples,1), ...
        'coherence_corrected', zeros(nPartSamples,1), ...
        'ypta_uncorrected', zeros(nPartSamples,1), ...
        'heightError_uncorrected', zeros(nPartSamples,1), ...
        'velocity_uncorrected', zeros(nPartSamples,1), ...
        'coherence_uncorrected', zeros(nPartSamples,1), ...
        'ypta_corrected', zeros(nPartSamples,1), ...
        'inds', partInds ...
    );

    labels = zeros(nPartSamples,1);
    correctedPhi = zeros(nPartSamples,nDays);
    uncorrectedPhi = zeros(nPartSamples,nDays);
    nShps = zeros(nPartSamples,1);
    ypta_corrected = zeros(nPartSamples,1);
    ypta_uncorrected = zeros(nPartSamples,1);


    for ii = 1:numel(partInds)
%         partInd = partInds(ii);
        sampleIndsInBB = indsInBufferedBlock(:,ii);
        % get data
        sVV = dataVV(sampleIndsInBB,:);
        sVH = dataVH(sampleIndsInBB,:);
        components = OI.Functions.get_dft_class_components(sVV, sVH, tsModel.nComp);
        [correctionCM, label] = tsModel.get_correction_cm(components);

        rawCm = (sVV'*sVV)./sqrt(sum(sVV.^2)'*sum(sVV.^2));
        correctedCm = rawCm .* correctionCM;
        corrected = OI.Functions.phase_triangulation(correctedCm);
        uncorrected = OI.Functions.phase_triangulation(rawCm);

        ypta_corrected(ii) = corrected'*correctedCm*corrected;
        ypta_uncorrected(ii) = uncorrected'*rawCm*uncorrected;
        labels(ii) = label;
        correctedPhi(ii,:) = corrected;
        uncorrectedPhi(ii,:) = uncorrected;
        nShps(ii) = sum(sampleIndsInBB~=maskIndex);
    end

    resultPartStruct.CORRECTED = correctedPhi;
    resultPartStruct.UNCORRECTED = uncorrectedPhi;
    resultPartStruct.LABELS = labels;
    resultPartStruct.nShps = nShps;
    resultPartStruct.ypta_corrected = ypta_corrected;
    resultPartStruct.ypta_uncorrected = ypta_uncorrected;
    
    % Get height error
    [cqCorrected, qCorrected] = OI.Functions.invert_height( ...
        correctedPhi, ...
        kFactors ...
    ); %#ok<ASGLU>
    [cqUncorrected, qUncorrected] = OI.Functions.invert_height( ...
        uncorrectedPhi, ...
        kFactors ...
    ); %#ok<ASGLU>
    % Remove height error
    correctedPhi = correctedPhi .* exp(1i*qCorrected .* kFactors);
    uncorrectedPhi = uncorrectedPhi .* exp(1i*qUncorrected .* kFactors);
    % Get velocity
    [cvCorrected, vCorrected] = OI.Functions.invert_velocity( ...
        correctedPhi, ...
        vPhiTs ...
    );
    [cvUncorrected, vUncorrected] = OI.Functions.invert_velocity( ...
        uncorrectedPhi, ...
        vPhiTs ...
    );

    resultPartStruct.heightError_corrected = qCorrected;
    resultPartStruct.velocity_corrected = vCorrected;
    resultPartStruct.coherence_corrected = cvCorrected;
    
    resultPartStruct.heightError_uncorrected = qUncorrected;
    resultPartStruct.velocity_uncorrected = vUncorrected;
    resultPartStruct.coherence_uncorrected = cvUncorrected;


    % save result object
    engine.save( resultPartTemplate, resultPartStruct)
    this.isFinished = true;
    end

    % Get geocoding information
    blockGeocode = engine.load( ...
        OI.Data.BlockGeocodedCoordinates().configure( ...
            'STACK', this.STACK, ...
            'BLOCK', this.BLOCK ...
        ) ...
    );

    % save a shape file
    shpName = OI.Functions.generate_shapefile_name(this, projObj);
    shpName = strrep(shpName, '.shp', sprintf('%s.shp', resultPartTemplate.part_string(this.PART, this.PARTS)));
    OI.Functions.ps_shapefile( ...
        shpName, ...
        blockGeocode.lat(partInds), ...
        blockGeocode.lon(partInds), ...
        {}, ... % displacements 2d Array
        {}, ... % datestr(timeSeries(1),'YYYYMMDD')
        qCorrected, ... % height error
        vCorrected, ... % velocity
        cvCorrected, ... % coherence
        labels, ... % labels
        nShps ... % samples in shp window
    );
    % save a shape file
    shpName = OI.Functions.generate_shapefile_name(this, projObj);
    shpName = strrep(shpName, '.shp', sprintf('_uncorrected_%s.shp', resultPartTemplate.part_string(this.PART, this.PARTS)));
    OI.Functions.ps_shapefile( ...
        shpName, ...
        blockGeocode.lat(partInds), ...
        blockGeocode.lon(partInds), ...
        {}, ... % displacements 2d Array
        {}, ... % datestr(timeSeries(1),'YYYYMMDD')
        qUncorrected, ... % height error
        vUncorrected, ... % velocity
        cvUncorrected ... % coherence
    );
    this.isFinished = true;
end

function [indsInBufferedBlock, maskIndex] = get_inds_in_buffered_block(this, engine, blockSize, windowSize, partInds)
    dsMaskObj = engine.load( ...
        OI.Data.SHPMasks().configure( ...
            'STACK', this.STACK, ...
            'BLOCK', this.BLOCK ...
        ) ...
    );

    if isempty(dsMaskObj)
        return
    end

    wOneSide = floor(windowSize / 2);
    middlePixel = ceil(prod(windowSize) / 2);middlePixel = ceil(prod(windowSize) / 2);
    bufferBlockSize = blockSize(1:2) + (wOneSide * 2);

    dx = (-wOneSide(2):wOneSide(2)).*ones(windowSize(1),1);
    dy = (-wOneSide(1):wOneSide(1))'.*ones(1,windowSize(2));

    inds = zeros(numel(dx),numel(partInds));
    for ii = 1:numel(partInds)
        [yi,xi] = ind2sub(blockSize, partInds(ii));
        inds(:,ii) = ...
        sub2ind(bufferBlockSize, ...
            yi+dy(:)+wOneSide(1), ...
            xi+dx(:)+wOneSide(2));    
    end

    dsMask = dsMaskObj.masks;
    dsMask(middlePixel,:) = 1; % Don't mask the target pixel
    indsInBufferedBlock = inds.*dsMask(:,partInds);

    %% Pull out samples
    maskIndex = prod(bufferBlockSize) + 1;
    indsInBufferedBlock(indsInBufferedBlock==0) = maskIndex;
    
end


function this = finalise_block(this, engine) %#ok<INUSD>
%     for partInd = 1:this.PARTS
%         resultPartTemplate = OI.Data.TSSqueeze().part(partInd,this.PARTS);
%         resultPart = engine.load( resultPartTemplate );
%         %% CONCAT
%     end
    this.isFinished = true;
end

function this = queue_jobs(this, engine)
    blockMap = engine.load( OI.Data.BlockMap() );
    projObj = engine.load( OI.Data.ProjectDefinition() );
    nJobs = 0;
    
    fieldDir = fileparts(OI.Data.TSSqueeze().identify(engine).filepath);
    fieldDirConts = dir(fieldDir);
    
    for stackInd = 1:numel(blockMap.stacks)
        ubi = blockMap.stacks(stackInd).usefulBlockIndices(:)';
        
        WANT = [160 170 169 159 158 115 124 134 148 114];
        if stackInd == 1
            ubi = unique([WANT ubi],'stable');
        end
        
        for blockInd = ubi
            priorObj = ...
                    OI.Data.TSSqueeze().configure( ...
                        'STACK', stackInd, ...
                        'BLOCK', blockInd).identify(engine);%, ...
            [~, fn, ext] = fileparts(priorObj.filepath);
            ext = priorObj.fileextension;
            if ~isempty(ext)
                ext = ['.' ext]; %#ok<AGROW>
            else
                ext = '';
            end

            if ~any(strcmpi([fn ext],{fieldDirConts.name}))
                allParts = true;
                for partInd = 1:this.PARTS
                    partString = OI.Data.TSSqueeze().configure( ...
                        'STACK', stackInd, ...
                        'BLOCK', blockInd ...
                        ).part_string(partInd, this.PARTS);
                    blockPlugin = this;
                    blockPlugin.STACK = stackInd;
                    blockPlugin.BLOCK = blockInd;
                    shpName = OI.Functions.generate_shapefile_name(blockPlugin, projObj);
                    shpName = strrep(shpName, '.shp', sprintf('_uncorrected_%s.shp', partString));

                    if exist(shpName,'file')
                        continue
                    end
                    
%                     if any(strcmpi(fnPart,{fieldDirConts.name}))
%                         continue
%                     end
                    nJobs = nJobs + 1;
                    allParts = false;
                    engine.requeue_job_at_index( ...
                        nJobs, ...
                        'STACK', stackInd, ...
                        'BLOCK', blockInd, ...
                        'PART', partInd ...
                    );%, ...
                    if nJobs > 200
                        return
                    end
                end
                if allParts
%                     nJobs = nJobs + 1;
%                     engine.requeue_job_at_index( ...
%                         nJobs, ...
%                         'STACK', stackInd, ...
%                         'BLOCK', blockInd ...
%                     );%, ...
                end
                
            end
        end
    end
    
    if nJobs == 0
        this.isFinished = true;
        engine.save( this.outputs{1} );
    end
end
end % methods

end % classdef