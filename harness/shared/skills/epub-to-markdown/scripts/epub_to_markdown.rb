#!/usr/bin/env ruby

require "fileutils"
require "optparse"

OPTIONS = {
  unwrap_blockquotes: false,
}.freeze

def parse_options
  options = OPTIONS.dup

  OptionParser.new do |parser|
    parser.banner = "Usage: epub_to_markdown.rb --src PATH --dest-dir PATH [options]"

    parser.on("--src PATH", "Source EPUB file") { |value| options[:src] = value }
    parser.on("--dest-dir PATH", "Destination folder for markdown and media") { |value| options[:dest_dir] = value }
    parser.on("--output-name NAME", "Markdown filename to write inside dest dir") { |value| options[:output_name] = value }
    parser.on("--start-marker TEXT", "Trim leading matter before this marker") { |value| options[:start_marker] = value }
    parser.on("--unwrap-blockquotes", "Unwrap top-level blockquotes during cleanup") { options[:unwrap_blockquotes] = true }
  end.parse!

  required = %i[src dest_dir]
  missing = required.select { |key| options[key].nil? || options[key].strip.empty? }
  raise OptionParser::MissingArgument, missing.join(", ") unless missing.empty?

  options[:src] = File.expand_path(options[:src])
  options[:dest_dir] = File.expand_path(options[:dest_dir])
  options[:output_name] ||= "#{File.basename(options[:src], File.extname(options[:src]))}.md"
  options
end

def run_in_dir!(dir, *cmd)
  ok = Dir.chdir(dir) { system(*cmd) }
  abort("command failed in #{dir}: #{cmd.join(' ')}") unless ok
end

def trim_to_marker(text, marker)
  return text unless marker

  idx = text.index(marker)
  raise "missing start marker: #{marker}" unless idx

  text[idx..]
end

def clean_inline_markup(text)
  text = text.gsub("\r", "")
  text = text.gsub("\u00A0", " ")
  text = text.gsub(/<svg\b.*?<\/svg>/m, "")
  text = text.gsub(/<img\s+[^>]*src="([^"]+)"[^>]*>/, '![](\1)')
  text = text.gsub(/<a\b[^>]*>(.*?)<\/a>/m, '\1')
  text = text.gsub(/<strong>(.*?)<\/strong>/m, '**\1**')
  text = text.gsub(/<samp\b[^>]*>(.*?)<\/samp>/m, '`\1`')
  text = text.gsub(/<figcaption><p>(.*?)<\/p><\/figcaption>/m, '\1')
  text = text.gsub(%r{<br\s*/?>}i, " / ")
  text = text.gsub(/<td\b[^>]*>/, "")
  text = text.gsub("</td>", "")
  text = text.gsub("<p>", "")
  text = text.gsub("</p>", "")
  text = text.gsub("<sup>", "")
  text = text.gsub("</sup>", "")

  text = text.gsub(/<span class="calibre10"><span class="bold">Chapter (\d+)\.\s+(.+?)<\/span><\/span>/, '## Chapter \1: \2')
  text = text.gsub(/<span class="calibre27"><span class="bold">(.+?)<\/span><\/span>/, '### \1')
  text = text.gsub(/<span class="calibre49"><span class="bold">(.+?)<\/span><\/span>/, '#### \1')

  text = text.gsub(/<span class="bold">(.+?)<\/span>/m, '**\1**')
  text = text.gsub(/<span class="italic">(.+?)<\/span>/m, '*\1*')
  text = text.gsub(/\*\*\*([^*]+)\*{5}:\*\*/, '**\1:**')
  text = text.gsub(/\*{5}([^*]+)\*{5}/, '*\1*')
  text = text.gsub(/<span\b[^>]*>/, "")
  text = text.gsub("</span>", "")
  text = text.gsub(/<div\b[^>]*>/, "")
  text = text.gsub("</div>", "")
  text = text.gsub(/<nav\b[^>]*>/, "")
  text = text.gsub("</nav>", "")
  text = text.gsub(/\]\(#(?:[^)]+\.html[^)]*|c\d+\.xhtml[^)]*)\)/, ']')

  text
end

def normalize_setext_headings(text)
  text = text.gsub(/^PART\s+([IVX]+)\\?\n\\?\n([^\n]+)\n=+\n/m, "# Part \\1\n\n## \\2\n")
  text = text.gsub(/^(\d+)\\?\n([^\n]+)\n=+\n/m, "## Chapter \\1: \\2\n")
  text
end

def normalize_figure_captions(text)
  text.gsub(/^\#{1,6}\s+(Figure\s+[^\n]+|FIGURE\s+[^\n]+)/, "**\\1**")
end

def rewrite_blocks(text, unwrap_blockquotes:)
  out = []
  lines = text.lines.map(&:chomp)
  i = 0

  while i < lines.length
    line = lines[i]

    if line.match?(/^> > `.*`\\?$/)
      block = []
      while i < lines.length && lines[i].match?(/^> > `.*`\\?$/)
        code = lines[i].sub(/^> > /, "")
        code = code.sub(/^`/, "").sub(/`\\?$/, "")
        block << code
        i += 1
      end
      out << "```"
      out.concat(block)
      out << "```"
      next
    end

    line = "" if line.strip.empty?
    line = line.sub(/\\$/, "") unless line.empty?
    line = line.sub(/^> > •\s+/, "- ")
    line = line.sub(/^> •\s+/, "- ")
    line = line.sub(/^(?:>\s*)+/, "> ") if line.start_with?(">")
    line = line.sub(/^> /, "") if unwrap_blockquotes
    line = "" if [">", "> "].include?(line)
    line = "" if line == "\\"

    unless line.start_with?("#", "##", "###", "####", "-", ">", "![", "[", "|", "```")
      if line.match?(/^Chapter \d+[.:] /)
        line = line.sub(/^Chapter (\d+)\.\s+/, '## Chapter \1: ')
      end
    end

    out << line
    i += 1
  end

  cleaned = out.join("\n")
  cleaned = cleaned.gsub(/^\[\*\*Click here to view code image\*\*\]\([^\n]+\)\n?/, "")
  cleaned = cleaned.gsub(/^<[^>]+>\s*$/, "")
  cleaned = normalize_setext_headings(cleaned)
  cleaned = normalize_figure_captions(cleaned)
  cleaned = cleaned.gsub(/\n{3,}/, "\n\n")
  cleaned.strip + "\n"
end

def verify_output!(text)
  failures = []
  failures << "found internal EPUB fragment links" if text.match?(/\]\(#(?:[^)]+\.html[^)]*|c\d+\.xhtml[^)]*)\)/)
  failures << "found raw calibre markers" if text.match?(/\.calibre|\{=html\}|\[\]\{#|:::/)
  failures << "found raw span/div/nav tags" if text.match?(%r{</?(?:span|div|nav)\b})
  failures << "found figure rendered as heading" if text.match?(/^\#{1,6}\s+(?:Figure|FIGURE)\b/)

  image_paths = text.scan(/!\[[^\]]*\]\(([^)]+)\)/).flatten
  bad_image_paths = image_paths.reject { |path| path.start_with?("media/", "http://", "https://") }
  failures << "found non-local media image paths: #{bad_image_paths.uniq.join(', ')}" unless bad_image_paths.empty?

  return if failures.empty?

  abort("verification failed: #{failures.join('; ')}")
end

options = parse_options
abort("source EPUB not found: #{options[:src]}") unless File.exist?(options[:src])

FileUtils.rm_rf(options[:dest_dir])
FileUtils.mkdir_p(options[:dest_dir])

run_in_dir!(
  options[:dest_dir],
  "pandoc",
  options[:src],
  "-f",
  "epub",
  "-t",
  "gfm",
  "--wrap=none",
  "--extract-media=media",
  "-o",
  options[:output_name],
)

output_path = File.join(options[:dest_dir], options[:output_name])
text = File.read(output_path)
text = clean_inline_markup(text)
text = trim_to_marker(text, options[:start_marker])
text = rewrite_blocks(text, unwrap_blockquotes: options[:unwrap_blockquotes])
verify_output!(text)
File.write(output_path, text)

puts output_path
