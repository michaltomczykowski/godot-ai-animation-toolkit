"""Narrow presentation contracts for exact independently known representatives."""
NEAREST_HOLD='nearest_two_key_loop_0_to_100_hold'


def apply_representative_contract(case):
    result=dict(case)
    if case.get('operation')=='animation_edit.set_interp' and case.get('variant')=='set_interp':
        result.update(require_progression=False,require_visible_difference=True,held_output_contract=NEAREST_HOLD)
    return result


def is_nearest_hold(case):
    return (case.get('operation')=='animation_edit.set_interp' and case.get('variant')=='set_interp'
        and case.get('held_output_contract')==NEAREST_HOLD)
