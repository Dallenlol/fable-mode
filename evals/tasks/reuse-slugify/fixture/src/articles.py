class Article:
    def __init__(self, title, body):
        self.title = title
        self.body = body

    def summary(self):
        from utils import truncate
        return truncate(self.body, 140)
