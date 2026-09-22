{ lib, desktopTheme, ... }:

let
  inherit (desktopTheme) hex raw;
  style = fg: bg: { fg = hex fg; bg = hex bg; };
  btopColors = {
    main_bg = "base"; main_fg = "text"; title = "text";
    hi_fg = "accent"; selected_bg = "accent"; selected_fg = "base";
    inactive_fg = "muted"; graph_text = "muted"; meter_bg = "overlay";
    proc_misc = "secondary"; cpu_box = "accent"; mem_box = "sage";
    net_box = "secondary"; proc_box = "muted"; div_line = "overlay";
  };
  gradient = name: start: mid: end: {
    "${name}_start" = start; "${name}_mid" = mid; "${name}_end" = end;
  };
  btopTheme = btopColors
    // gradient "temp" "sage" "warning" "urgent"
    // gradient "cpu" "sage" "accent" "urgent"
    // gradient "free" "overlay" "sage" "text"
    // gradient "cached" "overlay" "secondary" "text"
    // gradient "available" "overlay" "sage" "text"
    // gradient "used" "sage" "warning" "urgent"
    // gradient "download" "overlay" "sage" "text"
    // gradient "upload" "overlay" "accent" "text"
    // gradient "process" "sage" "accent" "urgent";
in
{
  programs.btop = {
    enable = true;
    settings.color_theme = "cat-cafe";
    themes.cat-cafe = lib.concatStrings (lib.mapAttrsToList
      (key: color: ''theme[${key}]="${hex color}"'' + "\n") btopTheme);
  };

  programs.yazi.theme = {
    app.overall = style "text" "base";
    mgr = {
      cwd.fg = hex "accent";
      border_style.fg = hex "overlay";
      find_keyword = { fg = hex "warning"; bold = true; };
      find_position.fg = hex "secondary";
      marker_copied = style "sage" "sage";
      marker_cut = style "urgent" "urgent";
      marker_marked = style "secondary" "secondary";
      marker_selected = style "accent" "accent";
      count_copied = style "base" "sage";
      count_cut = style "base" "urgent";
      count_selected = style "base" "accent";
    };
    tabs = { active = style "base" "accent"; inactive = style "muted" "surface"; };
    mode = {
      normal_main = style "base" "accent"; normal_alt = style "accent" "surface";
      select_main = style "base" "sage"; select_alt = style "sage" "surface";
      unset_main = style "base" "secondary"; unset_alt = style "secondary" "surface";
    };
    indicator = {
      parent = style "text" "overlay";
      current = style "base" "accent";
      preview.fg = hex "accent";
    };
    status = {
      overall = style "text" "surface";
      perm_sep.fg = hex "muted";
      perm_type.fg = hex "sage";
      perm_read.fg = hex "warning";
      perm_write.fg = hex "secondary";
      perm_exec.fg = hex "sage";
      progress_normal = style "sage" "surface";
      progress_error = style "urgent" "surface";
    };
    which = {
      border.fg = hex "accent"; cand.fg = hex "sage";
      rest.fg = hex "muted"; desc.fg = hex "text";
      separator_style.fg = hex "overlay";
    };
    confirm = {
      border.fg = hex "accent"; title.fg = hex "text";
      btn_yes = style "base" "accent"; btn_no = style "text" "surface";
    };
    spot = {
      border.fg = hex "accent"; title.fg = hex "text";
      tbl_col.fg = hex "secondary"; tbl_cell = style "base" "accent";
    };
    notify = {
      title_info.fg = hex "sage";
      title_warn.fg = hex "warning";
      title_error.fg = hex "urgent";
    };
    pick = { border.fg = hex "accent"; active.fg = hex "accent"; };
    input = { border.fg = hex "accent"; selected = style "base" "accent"; };
    cmp = { border.fg = hex "accent"; active = style "base" "accent"; };
    tasks = { border.fg = hex "accent"; hovered.fg = hex "secondary"; };
    help = { border.fg = hex "accent"; chord.fg = hex "sage"; hovered = style "base" "accent"; };
    filetype.rules = [
      { mime = "**/image/*"; fg = hex "warning"; }
      { mime = "**/{audio,video}/*"; fg = hex "secondary"; }
      { url = "*"; is = "orphan"; fg = hex "urgent"; }
      { url = "*"; is = "exec"; fg = hex "sage"; }
      { url = "*/"; fg = hex "accent"; }
      { url = "*"; fg = hex "text"; }
    ];
  };

  # Keep rebuild/update, aliases and shell integrations; only style the prompt
  # and syntax colors. No additional prompt engine or subprocesses are needed.
  programs.fish = {
    functions.fish_prompt = ''
      set -l last_status $status
      set_color ${raw "accent"}
      printf '%s' (prompt_pwd)
      if test $last_status -ne 0
        set_color ${raw "urgent"}
        printf ' [%s]' $last_status
      end
      set_color ${raw "muted"}
      printf ' › '
      set_color normal
    '';
    interactiveShellInit = ''
      set -g fish_color_normal ${raw "text"}
      set -g fish_color_command ${raw "accent"}
      set -g fish_color_param ${raw "text"}
      set -g fish_color_quote ${raw "sage"}
      set -g fish_color_redirection ${raw "secondary"}
      set -g fish_color_end ${raw "secondary"}
      set -g fish_color_error ${raw "urgent"}
      set -g fish_color_comment ${raw "muted"}
      set -g fish_color_autosuggestion ${raw "brightBlack"}
      set -g fish_color_operator ${raw "warning"}
      set -g fish_color_escape ${raw "warning"}
      set -g fish_color_search_match ${raw "base"} --background=${raw "accent"}
      set -g fish_color_selection ${raw "base"} --background=${raw "accent"}
      set -g fish_pager_color_prefix ${raw "accent"}
      set -g fish_pager_color_completion ${raw "text"}
      set -g fish_pager_color_description ${raw "muted"}
      set -g fish_pager_color_selected_background --background=${raw "overlay"}
    '';
  };

  # Git is already installed system-wide. The XDG config leaves Corey's existing
  # ~/.gitconfig identity untouched. bat and fzf are not installed: do not add them.
  programs.git = {
    enable = true;
    package = null;
    settings.color = {
      diff = { old = hex "urgent"; new = hex "sage"; meta = hex "accent"; frag = hex "secondary"; };
      status = { added = hex "sage"; changed = hex "secondary"; untracked = hex "urgent"; };
      branch = { current = hex "accent"; local = hex "text"; remote = hex "sage"; };
    };
  };
}
