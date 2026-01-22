import re

TASK_ID_PATTERN = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


def _wrap_task_id(func):
    def wrapper(*args, **kwargs):
        result = func(*args, **kwargs)
        if isinstance(result, str) and TASK_ID_PATTERN.fullmatch(result):
            print(f"docling_task_id={result}", flush=True)
        return result

    return wrapper


def _patch_gradio_ui():
    try:
        from docling_serve import gradio_ui  # type: ignore
    except Exception:
        return

    for name in ("process_url", "process_file"):
        if hasattr(gradio_ui, name):
            original = getattr(gradio_ui, name)
            if callable(original):
                setattr(gradio_ui, name, _wrap_task_id(original))


_patch_gradio_ui()
