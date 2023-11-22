
classdef DistributionEngine < OI.Engine

properties
    lastPostee = 0
end

methods (Access = protected)
    function run_plugin( this, job, messenger )
        if this.plugin.isArray && ~isempty( job.target )
            nextWorker = messenger.get_next_worker();
            if nextWorker == 0
                return %??
            end
            messenger.post_job( nextWorker, job.to_string() );
            this.lastPostee = nextWorker;
        else
            this.plugin = this.plugin.run( this, job.arguments );
            this.lastPostee = 0;
        end
    end % 

end % methods

end % classdef
