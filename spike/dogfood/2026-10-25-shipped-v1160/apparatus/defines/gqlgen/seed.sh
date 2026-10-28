set -eu
# The project `gqlgen init` made in the box (gqlgen v0.17.98), with the resolvers implemented by its
# developer and a field added to the schema since the last generate.
rm -rf /s/gql && mkdir -p /s && cp -a /opt/gql-proto /s/gql && cd /s/gql
python3 - <<'PY'
import pathlib
p = pathlib.Path("/s/gql/graph/schema.resolvers.go")
s = p.read_text()
s = s.replace('panic(fmt.Errorf("not implemented: CreateTodo - createTodo"))',
 '''// Written by the developer: store the todo with the next id and its owner.
	r.mu.Lock()
	defer r.mu.Unlock()
	t := &model.Todo{ID: fmt.Sprintf("T%d", len(r.todos)+1), Text: input.Text, User: &model.User{ID: input.UserID, Name: "user " + input.UserID}}
	r.todos = append(r.todos, t)
	return t, nil''')
s = s.replace('panic(fmt.Errorf("not implemented: Todos - todos"))',
 '''// Written by the developer: every todo, newest first.
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]*model.Todo, 0, len(r.todos))
	for i := len(r.todos) - 1; i >= 0; i-- {
		out = append(out, r.todos[i])
	}
	return out, nil''')
p.write_text(s)
r = pathlib.Path("/s/gql/graph/resolver.go")
r.write_text(r.read_text().replace("type Resolver struct{}", 'import (\n\t"sync"\n\n\t"example.com/notes/graph/model"\n)\n\ntype Resolver struct {\n\tmu    sync.Mutex\n\ttodos []*model.Todo\n}'))
g = pathlib.Path("/s/gql/graph/schema.graphqls")
g.write_text(g.read_text().replace("type Query {\n  todos: [Todo!]!\n}", "type Query {\n  todos: [Todo!]!\n  todo(id: ID!): Todo\n}"))
PY
. /ap/defines/gqlgen/env.sh
go build ./graph/model > /dev/null 2>&1 || true
install -m 755 /ap/defines/gqlgen/check.sh /s/gql-check.sh
