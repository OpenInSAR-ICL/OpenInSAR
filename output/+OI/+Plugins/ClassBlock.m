classdef ClassBlock < OI.Plugins.PluginBase
properties
    inputs = {OI.Data.BlockPsiSummary}
    outputs = {OI.Data.TsCorrectionSummary()}
    id = 'ClassBlock'
    STACK 
    BLOCK
    PART
    PARTS = 25;
end

methods
    function this = ClassBlock( varargin )
        this.isArray = true;
    end
    
function this = run(this, engine, varargin)
%     this.PART = 1;
%     this.STACK = 1;
%     this.BLOCK = 115;
    if isempty(this.STACK) || isempty(this.BLOCK)
        this = this.queue_jobs(engine);
        return;
    end

    this = this.squeeze_portion(engine);
    this.isFinished = true;
end %run



function this = squeeze_portion(this, engine)
    
    target = OI.Data.ClassificationComponents().configure( ...
        'STACK', this.STACK, ...
        'BLOCK', this.BLOCK, ...
        'PART', this.PART, ...
        'PARTS', this.PARTS );

    if target.identify(engine).exists()
        this.isFinished = true;
        return
    end
    
    windowSize = [5 21];

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

    % Classify, correct, squeeze
    partInds = this.part_inds(this.PART, this.PARTS, prod(blockSize(1:2)));
    indsInBufferedBlock = this.get_inds_in_buffered_block(this.STACK, this.BLOCK, engine, blockSize, windowSize, partInds);

    for ii = numel(partInds):-1:1
        sampleIndsInBB = indsInBufferedBlock(:,ii);
        sVV = dataVV(sampleIndsInBB,:);
        sVH = dataVH(sampleIndsInBB,:);
        components(ii, :) = OI.Functions.get_dft_class_components(sVV, sVH, tsModel.nComp);
    end
    
    % Get geocoding information
    blockGeocode = engine.load( ...
        OI.Data.BlockGeocodedCoordinates().configure( ...
            'STACK', this.STACK, ...
            'BLOCK', this.BLOCK ...
        ) ...
    );
    components(:,end+1:end+2) = [blockGeocode.lat(partInds) blockGeocode.lon(partInds)];
    
    engine.save(target, components);
    this.isFinished = true;
end

function this = queue_jobs(this, engine)
    blockMap = engine.load( OI.Data.BlockMap() );
    nJobs = 0;
    
    fieldDir = fileparts(OI.Data.TSSqueeze().identify(engine).filepath);
    fieldDirConts = dir(fieldDir);
    
    for stackInd = 1:numel(blockMap.stacks)
        ubi = blockMap.stacks(stackInd).usefulBlockIndices(:)';
%         160
% 159
% 150
% 149
% 158
% 168
% 115
% 105
        WANT = [105 115 158 168 160 150 159 149];
%         WANT = [160 170 169 159 158 115 124 134 148 114];
        if stackInd == 1
            ubi = unique([WANT ubi],'stable');
        end
        
        for blockInd = ubi
            for partInd = 1:this.PARTS
                target = OI.Data.ClassificationComponents().configure( ...
                    'STACK', this.STACK, ...
                    'BLOCK', this.BLOCK, ...
                    'PART', this.PART, ...
                    'PARTS', this.PARTS ).identify(engine);
                fp = [target.filepath '.mat'];
                if any(strcmpi(fp,{fieldDirConts.name}))
                    continue
                end
                nJobs = nJobs + 1;
                engine.requeue_job_at_index( ...
                    nJobs, ...
                    'STACK', stackInd, ...
                    'BLOCK', blockInd, ...
                    'PART', partInd ...
                );%, ...
                if nJobs > 200
                    return
                end
            end % part
        end % block
    end % stack
    
    if nJobs == 0
        this.isFinished = true;
        engine.save( this.outputs{1} );
    end
end % queue
end % methods

methods (Static = true)
    
function partInds = part_inds(PART, PARTS, nElements)
    partEnds = floor(linspace(1,nElements+1,PARTS+1));
    partInds = partEnds(PART):partEnds(PART+1)-1;
end

function [indsInBufferedBlock, maskIndex] = get_inds_in_buffered_block(STACK, BLOCK, engine, blockSize, windowSize, partInds)
    dsMaskObj = engine.load( ...
        OI.Data.SHPMasks().configure( ...
            'STACK', STACK, ...
            'BLOCK', BLOCK ...
        ) ...
    );

    if isempty(dsMaskObj)
        return
    end

    wOneSide = floor(windowSize / 2);
    middlePixel = ceil(prod(windowSize) / 2);
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
end
end % classdef