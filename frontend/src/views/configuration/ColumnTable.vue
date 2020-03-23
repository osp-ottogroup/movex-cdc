<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>
        Columns
      </th>
      <th>
        Insert-Trigger
      </th>
      <th>
        Update-Trigger
      </th>
      <th>
        Delete-Trigger
      </th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="column in columns" :key="column.id">
      <td>{{ column.name }}</td>
      <td>
        <input type="checkbox" v-model="column.yn_log_insert">
      </td>
      <td>
        <input type="checkbox" v-model="column.yn_log_update">
      </td>
      <td>
        <input type="checkbox" v-model="column.yn_log_delete">
      </td>
    </tr>
    </tbody>
  </table>
</template>

<script>
export default {
  name: 'ColumnTable',
  props: {
    columns: { type: Array, default: () => [] },
  },
};
</script>
