function RemoveAllComments(fullCode)
    return ProcessOutsideStrings(fullCode, function(segment)
        segment = segment:gsub("%-%-%[%[.-%]%]", "")
        segment = segment:gsub("%-%-[^\n]*", "")
        return segment
    end)
end