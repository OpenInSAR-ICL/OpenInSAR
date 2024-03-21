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

        % Copy over fields from varargin
        selfProps = properties(obj);
        for i = 1:2:length(varargin)-1
            if any(strcmp(varargin{i}, selfProps))
                obj.(varargin{i}) = varargin{i+1};
            end
        end

        required_fields = {'STACK', 'BLOCK', 'POLARISATION', 'METHOD'};
        for rf = required_fields
            if isempty(this.(rf{1}))
                error('PscSample:Constructor', 'Please specify the %s field in order that the sample can be identified', rf{1});
            end
        end
    end

end 

end