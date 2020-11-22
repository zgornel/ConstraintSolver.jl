"""
    simplify!(com)

Simplify constraints i.e by adding new constraints which uses an implicit connection between two constraints.
i.e an `all_different` does sometimes include information about the sum.
Return a list of newly added constraint ids
"""
function simplify!(com)
    added_constraint_idxs = Int[]
    # check if we have all_different and sum constraints
    b_all_different = false
    # (all different where every value is used)
    b_all_different_sum = false
    b_equal_to = false
    for constraint in com.constraints
        if isa(constraint.set, AllDifferentSetInternal)
            b_all_different = true
            if length(constraint.indices) == length(constraint.pvals)
                b_all_different_sum = true
            end
        elseif isa(constraint.fct, SAF) && isa(constraint.set, MOI.EqualTo)
            b_equal_to = true
        end
    end
    if b_all_different_sum && b_equal_to
        append!(added_constraint_idxs, simplify_all_different_and_equal_to(com))
    end
    return added_constraint_idxs
end

function simplify_all_different_and_equal_to(com)
    added_constraint_idxs = Int[]
    # for each all_different constraint
    # which has an implicit sum constraint
    # check which sum constraints are completely inside all different
    # which are partially inside
    # compute inside sum and total sum
    n_constraints_before = length(com.constraints)
    for constraint_idx = 1:length(com.constraints)
        constraint = com.constraints[constraint_idx]

        if isa(constraint.set, AllDifferentSetInternal)
            # check that the all different constraint uses every value
            if length(constraint.indices) == length(constraint.pvals)
                append!(added_constraint_idxs, simplify_all_different_inner_equal_to(com, constraint))
                append!(added_constraint_idxs, simplify_all_different_outer_equal_to(com, constraint, n_constraints_before))
            end
        end
    end
    return added_constraint_idxs
end

"""
    simplify_all_different_inner_equal_to(com, constraint::AllDifferentConstraint)

Add new sum constraint inside an alldifferent constraint to get restrict some variables more.
This function checks all sum constraints which are completely inside of the alldifferent constraint.

# Example
- [a,b,c,d,e] is the `AllDifferentConstraint`
- [a,b,c] is a sum constraint
- Add a new sum constraint for [d,e]
"""
function simplify_all_different_inner_equal_to(com, constraint::AllDifferentConstraint)
    @assert length(constraint.indices) == length(constraint.pvals)
    added_constraint_idxs = Int[]
    all_diff_sum = sum(constraint.pvals)
    in_sum = 0
    found_possible_constraint = false
    outside_indices = constraint.indices
    # go over all constraints that are completely inside alldifferent
    for sc_idx in constraint.sub_constraint_idxs
        sub_constraint = com.constraints[sc_idx]
        # if it's an equal_to constraint
        if isa(sub_constraint.fct, SAF) &&
            isa(sub_constraint.set, MOI.EqualTo)
            # the coefficients must be all 1
            if all(t.coefficient == 1 for t in sub_constraint.fct.terms)
                # compute sum inside all sum constraints
                found_possible_constraint = true
                in_sum += sub_constraint.set.value -
                    sub_constraint.fct.constant
                # for sum which are in alldifferent but not in sum constraints
                outside_indices = setdiff(outside_indices, sub_constraint.indices)
            end
        end
    end
    if found_possible_constraint && length(outside_indices) <= 4
        constraint_idx = length(com.constraints)+1
        # all_diff_sum is Int and in_sum must be as well as all variables are Int and coefficients 1
        lc = LinearConstraint(
            constraint_idx, outside_indices, ones(Int, length(outside_indices)),
            0, MOI.EqualTo{Int}(all_diff_sum - in_sum)
        )
        add_constraint!(
            com,
            lc
        )
        push!(added_constraint_idxs, constraint_idx)
    end
    return added_constraint_idxs
end

"""
    simplify_all_different_outer_equal_to(com, constraint::AllDifferentConstraint)

check if several sum constraints completely fill the sum constraint
if this is the case we can use the sum of the all different constraint
to get useful information about the sum of variables outside the
all different constraint but inside one of the sum constraints

# Example
[a,b,c,d] where [a,b,c] are in alldifferent and sum is 6
[a,b] in sum constraint == 3
[c,d] in sum constraint == 9
=> 6+d == 12 => d=6
"""
function simplify_all_different_outer_equal_to(com, constraint::AllDifferentConstraint, n_constraints_before)
    @assert length(constraint.indices) == length(constraint.pvals)
    add_sum_constraint = true
    all_diff_sum = sum(constraint.pvals)
    added_constraint_idxs = []

    total_sum = 0
    outside_indices = Int[]
    cons_indices_dict = arr2dict(constraint.indices)
    for variable_idx in keys(cons_indices_dict)
        found_sum_constraint = false
        for sub_constraint_idx in com.subscription[variable_idx]
            # don't mess with constraints added later on
            if sub_constraint_idx > n_constraints_before
                continue
            end
            sub_constraint = com.constraints[sub_constraint_idx]
            # it must be an equal constraint and all coefficients must be 1 otherwise we can't add a constraint
            if isa(sub_constraint.fct, SAF) &&
                isa(sub_constraint.set, MOI.EqualTo)
                if all(t.coefficient == 1 for t in sub_constraint.fct.terms)
                    found_sum_constraint = true
                    total_sum +=
                        sub_constraint.set.value -
                        sub_constraint.fct.constant
                    all_inside = true
                    for sub_variable_idx in sub_constraint.indices
                        if !haskey(cons_indices_dict, sub_variable_idx)
                            all_inside = false
                            push!(outside_indices, sub_variable_idx)
                        else
                            delete!(cons_indices_dict, sub_variable_idx)
                        end
                    end
                    break
                end
            end
        end
        if !found_sum_constraint
            add_sum_constraint = false
            break
        end
    end

    # make sure that there are not too many outside indices
    if add_sum_constraint && length(outside_indices) <= 4
        constraint_idx = length(com.constraints)+1
        lc = LinearConstraint(
            constraint_idx, outside_indices, ones(Int, length(outside_indices)),
            0, MOI.EqualTo{Int}(total_sum - all_diff_sum)
        )
        add_constraint!(
            com,
            lc
        )
        push!(added_constraint_idxs, constraint_idx)
    end
    return added_constraint_idxs
end