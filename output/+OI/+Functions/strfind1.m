function ind = strfind1(str,pattern,dir)
    starts = strfind(str,pattern);
    if dir==-1
        ind = starts(end);
    else 
        ind = starts(1);
    end 
    % no point optimising yet this is quick enough