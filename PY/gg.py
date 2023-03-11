from pagermaid import Config, log
from pagermaid.listener import listener
from pagermaid.enums import Message
from pagermaid.utils import lang, pip_install
pip_install("googlesearch-python")
from googlesearch import search

@listener(command="google", description=lang('google_des'), parameters="[query]")
async def google(message: Message):
    """ Searches Google for a string. """
    query = message.arguments
    if not query:
        if not message.reply_to_message:
            return await message.edit(lang('arg_error'))
        query = message.reply_to_message.text
    query = query.replace(' ', '+')
    if not Config.SILENT:
        message = await message.edit(lang('google_processing'))
    results = ""
    for i in search(query, num_results=5):
        try:
            title = i.title[:30] + '...'
            link = i.url
            results += f"\n<a href=\"{link}\">{title}</a> \n"
        except Exception:
            return await message.edit(lang('google_connection_error'))
    await message.edit(f"<b>Google</b> |<code>{query}</code>| 🎙 🔍 \n{results}", disable_web_page_preview=True)
    await log(f"{lang('google_success')} `{query}`")