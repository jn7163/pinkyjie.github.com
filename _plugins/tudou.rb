class TuDou < Liquid::Tag
  Syntax = /^\s*([^\s]+)(\s+(\d+)\s+(\d+)\s*)?/

  def initialize(tagName, markup, tokens)
    super

    if markup =~ Syntax then
      @id = $1

      if $2.nil? then
          @width = 560
          @height = 420
      else
          @width = $2.to_i
          @height = $3.to_i
      end
    else
      raise "在\"TuDou\"标签中未提供视频ID或提供的ID不合法。 Illgeal ID presented."
    end
  end

  def render(context)
    "<iframe src=\"http://www.tudou.com/programs/view/html5embed.action?code=#{@id}\" allowtransparency=\"true\" scrolling=\"no\" border=\"0\" frameborder=\"0\" style=\"width:#{@width}px;height:#{@height}px;\"></iframe>"
  end

  Liquid::Template.register_tag "tudou", self
end
