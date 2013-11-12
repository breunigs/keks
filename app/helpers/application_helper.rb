# encoding: utf-8

module ApplicationHelper
  def bool_to_symbol(bool)
    bool ? "✔" : "✘"
  end

  def perc(perc, all, err_message)
    return err_message if all.nil? || all == 0
    perc ||= 0
    all ||= 0
    number_to_percentage(perc/all.to_f*100, :precision => 0)
  end

  def trace_to_root_formatter(str)
    str = h str
    str.gsub!("\0open\0", %|<span class="traceToRootSplitter">|)
    str.gsub!("\0newline\0", %|<br/>|)
    str.gsub!("\0close\0", %|</span>|)
    str = %|<span class="traceToRootLine">#{str}</span>|
    str.html_safe
  end

  def url_for(options = nil)
    if Hash === options && Rails.env.production?
      options[:protocol] = 'https:'
    end
    super(options)
  end

  def redirect_to(options = {}, response_status = {})
    return super(options, response_status) unless Rails.env.production?

    case options
    when String
      if options.start_with?('http://')
        options.sub!(/^http:/, 'https:')
      elsif options =~ /^\w+:\/\//i
      else
        options = request.protocol.sub('http', 'https') + request.host_with_port + options
      end
    when :back
    when Proc
    else
      o = options.merge({:protocol => 'https:'}) rescue options
      url_for(o).sub(/^http:/, 'https:')
    end

    super(options, response_status)
  end


  def study_path_ids_from_param
    sp = params[:study_path]
    return [1] if !sp

    unless StudyPath.ids.include?(sp.to_i)
      logger.warn "Tried to access invalid study path id: #{sp}"
      return [1]
    end

    [1, sp.to_i].uniq
  end

  def difficulties_from_param
    diff = params[:difficulty].split("_").map(&:to_i) rescue []
    diff.reject! { |d| !Difficulty.ids.include?(d) }
    return diff if diff.any?

    return Difficulty.ids
  end

  def reject_unsuitable_questions!(qs)
    diff = difficulties_from_param
    sp = study_path_ids_from_param
    qs.reject! do |q|
      !diff.include?(q.difficulty) || !sp.include?(q.study_path) || !q.complete?
    end
  end

  # The completeness check is rather expensive. The idea is to request
  # more questions than required and exclude them later if they are
  # found to be incomplete. The trade off made is that we might be a
  # few questions short in some cases, but are faster on average. By
  # default 5 questions are presented each run, thus the default factor
  # of 1.6 loads three additional questions. If this value is too low,
  # a warning will logged (grep for INCREASE_FACTOR).
  INCREASE_FACTOR = 1.6

  # retrieves cnt questions out of the given set. The set may contain
  # incomplete questions, which are never returned though. May return
  # less questions than requested. If the user is logged in, it will
  # prefer questions not yet answered or answered incorrectly often.
  def get_question_sample(question_ids, cnt)
    if signed_in?
      logger.debug "### roulette selection"
      # select questions depending on how often they were answered
      # correctly.
      big_sample = roulette(question_ids, current_user, cnt)
    else
      logger.debug "### uniform selection"
      big_sample = question_ids.sample(cnt*INCREASE_FACTOR)
    end

    # resolve IDs into questions. Eager load most things required for
    # complete-check and presentation. The complete check is cached
    # after first run. Measurements show there is no downside to
    # including :reviews and :parent, even if they are not required.
    big_sample = Question.where(id: big_sample)
                  .includes(:answers, :reviews, :parent, :hints)

    samp = []
    big_sample.each do |s|
      samp << s if s.complete?
      # avoid completeness check if we have enough questions already
      break if samp.size == cnt
    end

    # warn if it’s possible that user desire could have been fulfilled.
    # If there are a lot of incomplete questions this may not be true,
    # so only increase INCREASE_FACTOR if you get this warning often and
    # if you question corpus is large enough.
    if samp.size < cnt && question_ids.size > cnt
      logger.warn "Got less questions than requested. Try increasing INCREASE_FACTOR."
      logger.warn "Available: #{question_ids*", "}"
      logger.warn "Selected: #{samp*", "}"
    end

    #~ dbgsamp = samp.map { |s| s.id }.join('  ')
    #~ dbgqs = qs.map { |s| s.id }.join('  ')
    #~ logger.debug "RANDOM DEBUG: cnt=#{cnt} samp=#{dbgsamp} quests=#{dbgqs}  signed_in=#{signed_in?}"

    samp
  end


  # roulette wheel selection for questions, depending on correct answer
  # ratio by user. Implementation by Jakub Hampl. Returns array of
  # question_ids.
  # http://stackoverflow.com/a/5243844/1684530
  def roulette(question_ids, user, n)
    probs = wrong_ratio_for(question_ids, user)

    selected = []
    (n*INCREASE_FACTOR).to_i.times do
      break if probs.empty?
      break if selected.size == n

      r, inc = rand * probs.sum, 0
      question_ids.each_index do |i|
        if r < (inc += probs[i])
          selected << question_ids[i]
          # make selection not pick sample twice
          question_ids.delete_at i
          probs.delete_at i
          break
        end
      end
    end

    return selected
  end

  def get_subquestion_for_answer(a, max_depth)
    sq = max_depth > 0 ? a.get_all_subquestions : []
    reject_unsuitable_questions!(sq)

    if sq.size > 0
      sq = get_question_sample(sq, 1)
      sq = json_for_question(sq.first, max_depth - 1)
    else
      sq = nil
    end
    sq
  end

  def etag(text = nil)
    # always bust browser cache in development mode so pages that can be
    # cached indefinitely in production mode get auto-reload support
    return Time.now.to_s if Rails.env.development?
    tag = []
    tag << GIT_REVISION if defined?(GIT_REVISION)
    tag << current_user.id if current_user
    tag << last_admin_or_reviewer_change
    tag << text unless text.blank?
    tag.join("_")
  end

  # retrieves question from URL parameters for all nested resources.
  # Usage: before_filter :get_question
  def get_question(redirect_on_error = questions_path)
    @question = Question.find(params[:question_id]) rescue nil
    unless @question
      flash[:warning] = "Frage mit dieser ID nicht gefunden."
      redirect_to redirect_on_error
    end
  end

  # for the given search hit, it returns the the field with all matches
  # highlighted. Optionally may specify to include whole stored text.
  # Via https://github.com/sunspot/sunspot/issues/111
  def search_highlight(search_hit, field, everything = false)
    phrases = []
    snippets = []

    search_hit.highlights(field).each do |highlight|
      phrases << highlight.instance_eval { @highlight }.scan(/@@@hl@@@([^@]+)@@@endhl@@@/)
      snippets << highlight.format { |w| w } unless everything
    end

    text = everything ? search_hit.stored(field).first : snippets.flatten.join

    highlight text, phrases.flatten
  end

  def search_snippet(search_hit, field, everything = false)
    t = search_highlight(search_hit, field, everything)
    return "" if t.blank?
    t = safe_join([content_tag(:span, field.to_s.humanize), t])
    content_tag(:div, t)
  end



  private


  # Counts how often each question has been answered by the given user
  # either correctly or incorrectly. Skipped questions are not taken
  # into account. Returns two hashes, the first with question_id to
  # times of correctly answered. The second is for wrong answers. Each
  # hash may omit question ids if the user never answered them.
  def answer_count_by_question_for(user)
    tmp = Stat.unscoped.where(:user_id => user.id, :skipped => false)
    correct = tmp.where(:correct => true).group(:question_id).size
    wrong = tmp.where(:correct => false).group(:question_id).size
    return correct, wrong
  end

  # calculates the correctly-answered-ratio for all given question IDs
  # and the given user. If a question was never answered, it gets a
  # ratio of 1. Every question receives at least a ratio of 0.1 to
  # prevent it from never appearing again after answering it correctly
  # once. Values thus range from 1.0 to 0.1. Higher values mean the
  # question has been answered wrong more often.
  def wrong_ratio_for(question_ids, user)
    # calculate ratio for each question how often it was answered in-
    # correctly by the user. Effectively, all the code does is:
    #   probs = questions.map { |q| [1 - q.correct_ratio_user(user), 0.1].max }
    # but a lot faster.
    correct, wrong = answer_count_by_question_for(user)

    question_ids.map do |qid|
      c = correct[qid] || 0
      w = wrong[qid] || 0
      cw = c+w
      [cw == 0 ? 1 : w/cw.to_f, 0.1].max
    end
  end
end
