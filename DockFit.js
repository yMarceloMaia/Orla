.pragma library

function fit(length, preferred, minimum, spacing, widgets, extraWidth, itemCount) {
    const gripWidth = 12;
    const fixed = 2 + widgets;
    const total = fixed + itemCount;
    if (total * (preferred + spacing) + gripWidth + extraWidth <= length)
        return {compact: false, edge: preferred, spacing: spacing, slots: itemCount};

    if (total * (preferred + spacing) + gripWidth <= length)
        return {compact: true, edge: preferred, spacing: spacing, slots: itemCount};

    const gap = 3;
    const fitted = Math.floor((length - gripWidth) / total) - gap;
    const edge = Math.min(preferred, Math.max(minimum, fitted));
    const capacity = Math.floor((length - gripWidth) / (edge + gap));
    const slots = capacity >= total ? itemCount : Math.max(0, capacity - fixed - 1);
    return {compact: true, edge: edge, spacing: gap, slots: slots};
}
