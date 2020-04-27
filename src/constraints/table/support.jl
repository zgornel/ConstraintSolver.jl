function Base.getindex(ts::TableSupport, com::ConstraintSolverModel, var_idx::Int, val::Int)
    val_idx = com.search_space[var_idx].init_val_to_index[val+com.search_space[var_idx].offset] 
    index_shift = ts.var_start[var_idx]-1+val_idx
    return ts.values[:,index_shift]
end