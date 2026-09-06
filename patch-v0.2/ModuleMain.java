package io.github.zhanfg.linearzh;

import android.content.Context;
import android.content.res.Resources;
import android.text.BoringLayout;
import android.text.StaticLayout;
import android.util.Log;
import android.widget.TextView;

import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

import io.github.libxposed.api.XposedModule;

public final class ModuleMain extends XposedModule {
    private static final String TAG = "LinearZh";
    private static final String TARGET = "app.linear";
    private static final String COMPOSE_SIMPLE = "androidx.compose.foundation.text.modifiers.TextStringSimpleElement";
    private static final String COMPOSE_ANNOTATED = "androidx.compose.foundation.text.modifiers.TextAnnotatedStringElement";
    private static final String COMPOSE_SELECTABLE = "androidx.compose.foundation.text.modifiers.SelectableTextAnnotatedStringElement";

    @Override
    public void onPackageReady(PackageReadyParam param) {
        if (!TARGET.equals(param.getPackageName())) return;
        int count = 0;
        count += hookResourceText();
        count += hookContextText();
        count += hookTextView();
        count += hookStaticLayout();
        count += hookBoringLayout();
        count += hookComposeText(param.getClassLoader());
        log(Log.INFO, TAG, "Linear Chinese hooks installed: " + count);
    }

    private int hookResourceText() {
        int count = 0;
        for (Method method : Resources.class.getDeclaredMethods()) {
            String name = method.getName();
            if (!(name.equals("getText") || name.equals("getString") ||
                    name.equals("getQuantityText") || name.equals("getQuantityString"))) continue;
            try {
                hook(method).intercept(chain -> {
                    Object result = chain.proceed();
                    if (result instanceof CharSequence text) return Translator.translateCharSequence(text);
                    return result;
                });
                count++;
            } catch (Throwable error) {
                log(Log.WARN, TAG, "Resource hook failed: " + method, error);
            }
        }
        return count;
    }

    private int hookContextText() {
        int count = 0;
        for (Method method : Context.class.getDeclaredMethods()) {
            String name = method.getName();
            if (!(name.equals("getText") || name.equals("getString"))) continue;
            try {
                hook(method).intercept(chain -> {
                    Object result = chain.proceed();
                    if (result instanceof CharSequence text) return Translator.translateCharSequence(text);
                    return result;
                });
                count++;
            } catch (Throwable error) {
                log(Log.WARN, TAG, "Context hook failed: " + method, error);
            }
        }
        return count;
    }

    private int hookTextView() {
        int count = 0;
        for (Method method : TextView.class.getDeclaredMethods()) {
            if (!method.getName().equals("setText")) continue;
            Class<?>[] types = method.getParameterTypes();
            if (types.length == 0 || !CharSequence.class.isAssignableFrom(types[0])) continue;
            try {
                hook(method).intercept(chain -> {
                    Object[] args = chain.getArgs().toArray();
                    if (args.length > 0 && args[0] instanceof CharSequence text) {
                        args[0] = Translator.translateCharSequence(text);
                    }
                    return chain.proceed(args);
                });
                count++;
            } catch (Throwable error) {
                log(Log.WARN, TAG, "TextView hook failed: " + method, error);
            }
        }
        return count;
    }

    private int hookStaticLayout() {
        int count = 0;
        try {
            for (Method method : StaticLayout.Builder.class.getDeclaredMethods()) {
                if (!method.getName().equals("obtain") || !Modifier.isStatic(method.getModifiers())) continue;
                Class<?>[] types = method.getParameterTypes();
                if (types.length == 0 || !CharSequence.class.isAssignableFrom(types[0])) continue;
                hook(method).intercept(chain -> {
                    Object[] args = chain.getArgs().toArray();
                    if (args.length > 0 && args[0] instanceof CharSequence text) {
                        String before = text.toString();
                        CharSequence after = Translator.translateCharSequence(text);
                        if (!before.contentEquals(after)) {
                            args[0] = after;
                            if (args.length > 2 && args[1] instanceof Integer && args[2] instanceof Integer) {
                                args[1] = 0;
                                args[2] = after.length();
                            }
                        }
                    }
                    return chain.proceed(args);
                });
                count++;
            }
        } catch (Throwable error) {
            log(Log.WARN, TAG, "StaticLayout hook setup failed", error);
        }
        return count;
    }

    private int hookBoringLayout() {
        int count = 0;
        for (Method method : BoringLayout.class.getDeclaredMethods()) {
            if (!method.getName().equals("make") || !Modifier.isStatic(method.getModifiers())) continue;
            Class<?>[] types = method.getParameterTypes();
            if (types.length == 0 || !CharSequence.class.isAssignableFrom(types[0])) continue;
            try {
                hook(method).intercept(chain -> {
                    Object[] args = chain.getArgs().toArray();
                    if (args.length > 0 && args[0] instanceof CharSequence text) {
                        args[0] = Translator.translateCharSequence(text);
                    }
                    return chain.proceed(args);
                });
                count++;
            } catch (Throwable error) {
                log(Log.WARN, TAG, "BoringLayout hook failed: " + method, error);
            }
        }
        return count;
    }

    /**
     * Linear 1.99.0 is Compose-heavy. Text() normally becomes one of these modifier elements,
     * bypassing TextView and often bypassing the resource call sites we can reliably intercept.
     * Hooking the display element keeps the translation at the render boundary instead of
     * changing Linear's model/network data.
     */
    private int hookComposeText(ClassLoader classLoader) {
        int count = 0;
        count += hookComposeSimpleString(classLoader);
        count += hookComposeAnnotated(classLoader, COMPOSE_ANNOTATED);
        count += hookComposeAnnotated(classLoader, COMPOSE_SELECTABLE);
        return count;
    }

    private int hookComposeSimpleString(ClassLoader classLoader) {
        int count = 0;
        try {
            Class<?> type = Class.forName(COMPOSE_SIMPLE, false, classLoader);
            for (Constructor<?> constructor : type.getDeclaredConstructors()) {
                Class<?>[] types = constructor.getParameterTypes();
                if (types.length == 0 || types[0] != String.class) continue;
                constructor.setAccessible(true);
                hook(constructor).intercept(chain -> {
                    Object[] args = chain.getArgs().toArray();
                    if (args.length > 0 && args[0] instanceof String text) {
                        args[0] = Translator.translate(text);
                    }
                    return chain.proceed(args);
                });
                count++;
            }
        } catch (Throwable error) {
            log(Log.WARN, TAG, "Compose simple text hook failed", error);
        }
        return count;
    }

    private int hookComposeAnnotated(ClassLoader classLoader, String elementClassName) {
        int count = 0;
        try {
            Class<?> element = Class.forName(elementClassName, false, classLoader);
            for (Constructor<?> elementConstructor : element.getDeclaredConstructors()) {
                Class<?>[] parameterTypes = elementConstructor.getParameterTypes();
                if (parameterTypes.length == 0) continue;
                Class<?> annotatedType = parameterTypes[0];
                Constructor<?> stringConstructor = findStringConstructor(annotatedType);
                if (stringConstructor == null) continue;
                elementConstructor.setAccessible(true);
                stringConstructor.setAccessible(true);
                hook(elementConstructor).intercept(chain -> {
                    Object[] args = chain.getArgs().toArray();
                    if (args.length == 0 || args[0] == null) return chain.proceed(args);
                    String before = args[0].toString();
                    String after = Translator.translate(before);
                    if (!before.equals(after)) {
                        try {
                            args[0] = newAnnotatedString(stringConstructor, after);
                        } catch (Throwable error) {
                            log(Log.WARN, TAG, "Could not rebuild Compose annotated text", error);
                        }
                    }
                    return chain.proceed(args);
                });
                count++;
            }
        } catch (Throwable error) {
            log(Log.WARN, TAG, "Compose annotated text hook failed: " + elementClassName, error);
        }
        return count;
    }

    private static Constructor<?> findStringConstructor(Class<?> type) {
        for (Constructor<?> constructor : type.getDeclaredConstructors()) {
            Class<?>[] params = constructor.getParameterTypes();
            if (params.length == 1 && params[0] == String.class) return constructor;
        }
        return null;
    }

    private static Object newAnnotatedString(Constructor<?> constructor, String text) throws Exception {
        return constructor.newInstance(text);
    }
}
