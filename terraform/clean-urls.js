// CloudFront Function (viewer request): clean URLs for xavieraws.com
//   /about        -> serves about.html
//   /about.html   -> 301 redirect to /about
//   /elements.html, /generic.html (old names) -> 301 to /about, /skills
function handler(event) {
  var req = event.request;
  var uri = req.uri;

  var redirects = {
    '/index.html':    '/',
    '/elements.html': '/about',
    '/generic.html':  '/skills',
    '/about.html':    '/about',
    '/skills.html':   '/skills',
    '/blog.html':     '/blog'
  };
  if (redirects[uri]) {
    return {
      statusCode: 301,
      statusDescription: 'Moved Permanently',
      headers: { location: { value: redirects[uri] } }
    };
  }

  var last = uri.split('/').pop();
  if (uri !== '/' && last.indexOf('.') === -1) {
    req.uri = uri.replace(/\/$/, '') + '.html';
  }
  return req;
}