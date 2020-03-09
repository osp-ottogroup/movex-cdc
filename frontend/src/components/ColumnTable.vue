<template>
  <table class="table is-striped is-hoverable">
    <thead>
    <tr>
      <th>
        Columns
      </th>
    </tr>
    </thead>
    <tbody>
    <tr v-for="column in columns" :key="column.id">
      <td>{{ column.name }}</td>
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
