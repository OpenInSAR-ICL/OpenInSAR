classdef PscSample < OI.Data.DataObj
% A container for SAR measurement time series, intended for sampling Persistent
% Scatterer Candidates (PSCs) from a stack of SAR images.

properties
    id = 'PscSample_s$STACK$_b$BLOCK$_p$POLARISATION$_m$METHOD$'
    generator = 'PscSampling'
    STACK = ''
    BLOCK = ''
    POLARISATION = ''
    METHOD = ''
    type = ''

    % common to all sample sets
    sampleStability = []
    samplePhase = []
    sampleAz = []
    sampleRg = []

    % optional
    coherence = []
    velocity = []
    heightError = []
    displacement = []
    sampleStabilityThreshold = []
    sampleMask = []

    % specific to block-wise sample
    blockInfo = []
    
    % specific to global sample
    sampleBlock = []
    sampleLLE = []

end

methods

    function obj = PscSample(varargin)
        obj.hasFile = true;
        obj.filepath = '$WORK$/fields/$id$';
        obj.fileextension = 'mat';
    end

end 

end