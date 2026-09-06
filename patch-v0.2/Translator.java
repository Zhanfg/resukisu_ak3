package io.github.zhanfg.linearzh;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class Translator {
    private static final Loaded LOADED = load();
    private static final Map<String, String> EXACT = LOADED.exact;
    private static final Map<String, String> NORMALIZED = LOADED.normalized;
    private static final List<TemplateRule> TEMPLATES = LOADED.templates;

    private Translator() {}

    static String translate(String source) {
        if (source == null || source.isEmpty()) return source;

        String direct = EXACT.get(source);
        if (direct != null) return direct;

        String normalized = normalize(source);
        String normalizedHit = NORMALIZED.get(normalized);
        if (normalizedHit != null) return normalizedHit;

        for (TemplateRule rule : TEMPLATES) {
            String translated = rule.tryTranslate(source);
            if (translated != null) return translated;
        }
        return source;
    }

    static CharSequence translateCharSequence(CharSequence source) {
        if (source == null || source.length() == 0) return source;
        String original = source.toString();
        String translated = translate(original);
        return original.equals(translated) ? source : translated;
    }

    private static String normalize(String source) {
        String s = source.replace('\u00A0', ' ')
                .replace('\u2018', '\'')
                .replace('\u2019', '\'')
                .replace('\u201C', '"')
                .replace('\u201D', '"')
                .trim();
        return s.replaceAll("\\s+", " ");
    }

    private static Loaded load() {
        Map<String, String> exact = new HashMap<>();
        Map<String, String> normalized = new HashMap<>();
        List<TemplateRule> templates = new ArrayList<>();

        try (InputStream in = Translator.class.getResourceAsStream("/translations.tsv")) {
            if (in == null) return new Loaded(Collections.emptyMap(), Collections.emptyMap(), Collections.emptyList());
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    if (line.isEmpty() || line.charAt(0) == '#') continue;
                    int tab = line.indexOf('\t');
                    if (tab <= 0 || tab == line.length() - 1) continue;
                    String source = line.substring(0, tab);
                    String target = line.substring(tab + 1);
                    exact.put(source, target);
                    normalized.putIfAbsent(normalize(source), target);
                    if (source.indexOf('%') >= 0) {
                        TemplateRule rule = TemplateRule.compile(source, target);
                        if (rule != null) templates.add(rule);
                    }
                }
            }
        } catch (Throwable ignored) {
            return new Loaded(Collections.emptyMap(), Collections.emptyMap(), Collections.emptyList());
        }

        return new Loaded(
                Collections.unmodifiableMap(exact),
                Collections.unmodifiableMap(normalized),
                Collections.unmodifiableList(templates)
        );
    }

    private record Loaded(Map<String, String> exact, Map<String, String> normalized, List<TemplateRule> templates) {}

    private static final class TemplateRule {
        private static final Pattern PLACEHOLDER = Pattern.compile("%(?:(\\d+)\\$)?([sd])");
        private final Pattern sourcePattern;
        private final String targetTemplate;
        private final Map<Integer, Integer> argToGroup;

        private TemplateRule(Pattern sourcePattern, String targetTemplate, Map<Integer, Integer> argToGroup) {
            this.sourcePattern = sourcePattern;
            this.targetTemplate = targetTemplate;
            this.argToGroup = argToGroup;
        }

        static TemplateRule compile(String source, String target) {
            Matcher matcher = PLACEHOLDER.matcher(source);
            StringBuilder regex = new StringBuilder("^");
            Map<Integer, Integer> argToGroup = new HashMap<>();
            int last = 0;
            int implicitArg = 1;
            int group = 1;
            boolean found = false;
            while (matcher.find()) {
                found = true;
                regex.append(Pattern.quote(source.substring(last, matcher.start())));
                String type = matcher.group(2);
                regex.append("d".equals(type) ? "(-?\\d+)" : "(.+?)");
                int argIndex = matcher.group(1) != null ? Integer.parseInt(matcher.group(1)) : implicitArg++;
                argToGroup.putIfAbsent(argIndex, group++);
                last = matcher.end();
            }
            if (!found) return null;
            regex.append(Pattern.quote(source.substring(last))).append('$');
            try {
                return new TemplateRule(Pattern.compile(regex.toString(), Pattern.DOTALL), target, argToGroup);
            } catch (Throwable ignored) {
                return null;
            }
        }

        String tryTranslate(String input) {
            Matcher matcher = sourcePattern.matcher(input);
            if (!matcher.matches()) return null;

            Matcher placeholders = PLACEHOLDER.matcher(targetTemplate);
            StringBuffer out = new StringBuffer();
            int implicitArg = 1;
            while (placeholders.find()) {
                int argIndex = placeholders.group(1) != null ? Integer.parseInt(placeholders.group(1)) : implicitArg++;
                Integer group = argToGroup.get(argIndex);
                String value = group == null ? placeholders.group() : matcher.group(group);
                placeholders.appendReplacement(out, Matcher.quoteReplacement(value));
            }
            placeholders.appendTail(out);
            return out.toString();
        }
    }
}
