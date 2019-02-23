function F = placement(sz, loc, F1)
% Placing a subcube in a bigger cube (helper function).
%
% Amin Nejat

    loc = round(loc);
    
    center = round([size(F1, 1), size(F1, 2), size(F1, 3)]/2);
    
    rel = round(center - 1);
    reu = round(center - 1);
    
    rel(loc - center - 1 < 0) = loc(loc - center - 1 < 0) - 1;
    reu(loc + center - sz > 0) = sz(loc + center - sz > 0) - loc(loc + center - sz > 0);
    
    F = zeros([sz, size(F1, 4)]);
    
    F(loc(1)-rel(1): loc(1)+reu(1), loc(2)-rel(2): loc(2)+reu(2), loc(3)-rel(3): loc(3)+reu(3), :) = ...
        F1(center(1)-rel(1): center(1)+reu(1), center(2)-rel(2): center(2)+reu(2), center(3)-rel(3): center(3)+reu(3), :);
end