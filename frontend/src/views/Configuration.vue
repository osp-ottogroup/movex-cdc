<template>
  <div class="columns is-centered">
    <div class="column is-2">
      <table class="table is-striped is-hoverable">
        <thead>
          <tr>
            <th>
              Schemas
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="schema in schemas" :key="schema">
            <td>{{ schema }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="column is-2">
      <table class="table is-striped is-hoverable">
        <thead>
        <tr>
          <th>
            Tables
          </th>
        </tr>
        </thead>
        <tbody>
        <tr v-for="table in tables" :key="table">
          <td>{{ table }}</td>
        </tr>
        </tbody>
      </table>
    </div>

    <div class="column is-4">
      <table class="table is-striped is-hoverable">
        <thead>
        <tr>
          <th>
            Columns
          </th>
        </tr>
        </thead>
        <tbody>
        <tr v-for="column in columns" :key="column">
          <td>{{ column }}</td>
        </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<script>
export default {
  name: 'configuration',
  data() {
    return {
      schemas: ['Schema 1', 'Schema 2', 'Schema 3'],
      tables: ['Table 1', 'Table 2', 'Table 3'],
      columns: ['Column 1', 'Column 2', 'Column 3'],
    };
  },
};
</script>
