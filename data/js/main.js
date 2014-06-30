var to_apt_instr_form = $(".add_to_apt_instr_form");
if (to_apt_instr_form.length) {
    to_apt_instr_form.on('submit', function() {
        $('#add_to_apt_instr_modal').find('.pkg_series').text(to_apt_instr_form.find('select.series_select')[0].value);
        $('#add_to_apt_instr_modal').find('.pkg_arch').text(to_apt_instr_form.find('select.arch_select')[0].value);
        $('#add_to_apt_instr_modal').modal('show');

        return false;
    });

    to_apt_instr_form.find('select').on('change', function() {
        if (to_apt_instr_form.find('select.series_select')[0].value && to_apt_instr_form.find('select.arch_select')[0].value) {
            to_apt_instr_form.find('button').removeAttr('disabled');
        } else {
            to_apt_instr_form.find('button').attr('disabled', 'disabled');
        }
    });
}